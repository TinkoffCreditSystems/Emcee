import Foundation
import ProcessController
import SynchronousWaiter

public final class FakeProcessController: ProcessController {
    public var subprocess: Subprocess

    public init(subprocess: Subprocess, processStatus: ProcessStatus = .notStarted) {
        self.subprocess = subprocess
        self.overridedProcessStatus = processStatus
    }
    
    public var processName: String {
        return try! subprocess.arguments[0].stringValue().lastPathComponent
    }
    
    public var processId: Int32 {
        return 0
    }
    
    public var onStart: (FakeProcessController) -> () = { _ in }
    public func start() {
        onStart(self)
    }
    
    public func waitForProcessToDie() {
        try? SynchronousWaiter().waitWhile { isProcessRunning }
    }
    
    public var overridedProcessStatus: ProcessStatus = .notStarted
    
    public func processStatus() -> ProcessStatus {
        return overridedProcessStatus
    }
    
    public var signalsSent = [Int32]()
    
    public func send(signal: Int32) {
        signalsSent.append(signal)
    }
    
    public func terminateAndForceKillIfNeeded() {
        send(signal: SIGTERM)
        overridedProcessStatus = .terminated(exitCode: SIGTERM)
    }
    
    public func interruptAndForceKillIfNeeded() {
        send(signal: SIGINT)
        overridedProcessStatus = .terminated(exitCode: SIGINT)
    }
    
    // Stdout
    
    public var stdoutListeners = [StdoutListener]()
    
    public func onStdout(listener: @escaping StdoutListener) {
        stdoutListeners.append(listener)
    }
    
    public func broadcastStdout(data: Data) {
        stdoutListeners.forEach { $0(self, data, { }) }
    }
    
    // Stderr
    
    public var stderrListeners = [StdoutListener]()
    
    public func onStderr(listener: @escaping StderrListener) {
        stderrListeners.append(listener)
    }
    
    public func broadcastStderr(data: Data) {
        stderrListeners.forEach { $0(self, data, { }) }
    }
    
    // Silence
    
    public var signalListeners = [SignalListener]()
    
    public func onSignal(listener: @escaping SignalListener) {
        signalListeners.append(listener)
    }
    
    public func broadcastSignal(_ signal: Int32) {
        signalListeners.forEach { $0(self, signal, { }) }
    }
}
