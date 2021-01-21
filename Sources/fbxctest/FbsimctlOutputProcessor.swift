import AtomicModels
import Dispatch
import Foundation
import JSONStream
import Logging
import ProcessController

public final class FbsimctlOutputProcessor: JSONReaderEventStream {
    private let processController: ProcessController
    private let receivedEvents = AtomicValue<[FbSimCtlEventCommonFields]>([])
    private let jsonStream: AppendableJSONStream
    private let decoder = JSONDecoder()
    private let jsonReaderQueue = DispatchQueue(label: "ru.avito.FbsimctlOutputProcessor.jsonReaderQueue")
    
    public init(
        jsonStream: AppendableJSONStream = BlockingArrayBasedJSONStream(),
        processController: ProcessController
    ) {
        self.jsonStream = jsonStream
        self.processController = processController
    }

    @discardableResult
    public func waitForEvent(
        type: FbSimCtlEventType,
        name: FbSimCtlEventName,
        timeout: TimeInterval
    ) throws -> [FbSimCtlEventCommonFields] {
        let startTime = Date().timeIntervalSinceReferenceDate
        startProcessingJSONStream()
        defer { jsonStream.close() }
        
        processController.onStdout { [weak self] _, data, unsubscriber in
            guard let strongSelf = self else { return unsubscriber() }
            strongSelf.jsonStream.append(data: data)
        }
        processController.start()
        
        while shouldKeepWaitingForEvent(type: type, name: name) {
            guard Date().timeIntervalSinceReferenceDate - startTime < timeout else {
                Logger.debug("Did not receive event \(name) \(type) within \(timeout) seconds", processController.subprocessInfo)
                processController.interruptAndForceKillIfNeeded()
                throw FbsimctlEventWaitError.timeoutOccured(name, type)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        let filteredReceivedEvents = filterReceivedEvents(type: type, name: name)
        if filteredReceivedEvents.isEmpty {
            throw FbsimctlEventWaitError.processTerminatedWithoutEvent(pid: processController.processId, name, type)
        }
        return filteredReceivedEvents
    }
    
    // MARK: - Private
    
    private func shouldKeepWaitingForEvent(type: FbSimCtlEventType, name: FbSimCtlEventName) -> Bool {
        return filterReceivedEvents(type: type, name: name).isEmpty
    }

    private func filterReceivedEvents(
        type: FbSimCtlEventType,
        name: FbSimCtlEventName
    ) -> [FbSimCtlEventCommonFields] {
        return receivedEvents.currentValue().filter { $0.name == name && $0.type == type }
    }

    private func startProcessingJSONStream() {
        jsonReaderQueue.async {
            let reader = JSONReader(inputStream: self.jsonStream, eventStream: self)
            do {
                try reader.start()
            } catch {
                let context = String(data: Data(reader.collectedBytes), encoding: .utf8)
                Logger.error("JSON stream processing failed: \(error). Context: \(String(describing: context))")
            }
        }
    }
    
    private func processSingleLiveEvent(_ bytes: [UInt8]) {
        processSingleLiveEvent(eventData: Data(bytes))
    }
    
    private func processSingleLiveEvent(eventData: Data) {
        if let event = try? decoder.decode(FbSimCtlCreateEndedEvent.self, from: eventData) {
            Logger.verboseDebug("Parsed event: \(event)", processController.subprocessInfo)
            receivedEvents.withExclusiveAccess { $0.append(event) }
            return
        }

        if let event = try? decoder.decode(FbSimCtlEventWithStringSubject.self, from: eventData) {
            Logger.verboseDebug("Parsed event: \(event)", processController.subprocessInfo)
            receivedEvents.withExclusiveAccess { $0.append(event) }
            return
        }

        do {
            let event = try decoder.decode(FbSimCtlEvent.self, from: eventData)
            receivedEvents.withExclusiveAccess { $0.append(event) }
            Logger.verboseDebug("Parsed event: \(event)", processController.subprocessInfo)
        } catch {
            let dataStringRepresentation = String(data: eventData, encoding: .utf8)
            Logger.error("Failed to parse event: '\(String(describing: dataStringRepresentation))': \(error)", processController.subprocessInfo)
        }
    }
    
    // MARK: - JSONReaderEventStream
    
    public func newArray(_ array: NSArray, bytes: [UInt8]) {
        processSingleLiveEvent(bytes)
    }
    
    public func newObject(_ object: NSDictionary, bytes: [UInt8]) {
        processSingleLiveEvent(bytes)
    }
}
