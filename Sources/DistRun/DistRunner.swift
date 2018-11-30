import EventBus
import Foundation
import Models
import ResourceLocationResolver
import RuntimeDump
import ScheduleStrategy
import TempFolder

public final class DistRunner {    
    private let eventBus: EventBus
    private let distRunConfiguration: DistRunConfiguration
    private let tempFolder: TempFolder
    private let resourceLocationResolver: ResourceLocationResolver
    private let distRunDeployer: DistRunDeployer
    
    public init(
        eventBus: EventBus,
        distRunConfiguration: DistRunConfiguration,
        resourceLocationResolver: ResourceLocationResolver,
        tempFolder: TempFolder)
    {
        self.eventBus = eventBus
        self.distRunConfiguration = distRunConfiguration
        self.tempFolder = tempFolder
        self.resourceLocationResolver = resourceLocationResolver
        self.distRunDeployer = DistRunDeployer(distRunConfiguration: distRunConfiguration, tempFolder: tempFolder)
    }
    
    public func run() throws -> [TestingResult] {
        let queueServer = QueueServer(
            eventBus: eventBus,
            workerConfigurations: createWorkerConfigurations(),
            reportAliveInterval: distRunConfiguration.reportAliveInterval,
            numberOfRetries: distRunConfiguration.testRunExecutionBehavior.numberOfRetries)
        queueServer.add(buckets: try prepareQueue())
        let port = try queueServer.start()
        try distRunDeployer.deployAndStartLaunchdJob(serverPort: port)
        return try queueServer.waitForQueueToFinish()
    }
    
    private func prepareQueue() throws -> [Bucket] {        
        let splitter = distRunConfiguration.remoteScheduleStrategyType.bucketSplitter()
        return splitter.generate(
            inputs: distRunConfiguration.testEntryConfigurations,
            splitInfo: BucketSplitInfo(
                numberOfDestinations: UInt(distRunConfiguration.destinations.count),
                toolResources: distRunConfiguration.auxiliaryResources.toolResources
            )
        )
    }
    
    private func createWorkerConfigurations() -> WorkerConfigurations {
        let configurations = WorkerConfigurations()
        for destination in distRunConfiguration.destinations {
            configurations.add(
                workerId: destination.identifier,
                configuration: distRunConfiguration.workerConfiguration(destination: destination))
        }
        return configurations
    }
}
