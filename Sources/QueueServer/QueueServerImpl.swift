import AutomaticTermination
import BalancingBucketQueue
import BucketQueue
import DateProvider
import Deployer
import DistWorkerModels
import Foundation
import Logging
import PortDeterminer
import QueueCommunication
import QueueModels
import RESTInterfaces
import RESTMethods
import RESTServer
import RequestSender
import ScheduleStrategy
import SocketModels
import Swifter
import SynchronousWaiter
import UniqueIdentifierGenerator
import WorkerAlivenessProvider
import WorkerCapabilities

public final class QueueServerImpl: QueueServer {
    private let bucketProvider: BucketProviderEndpoint
    private let bucketResultRegistrar: BucketResultRegistrar
    private let deploymentDestinationsHandler: DeploymentDestinationsEndpoint
    private let disableWorkerHandler: DisableWorkerEndpoint
    private let enableWorkerHandler: EnableWorkerEndpoint
    private let httpRestServer: HTTPRESTServer
    private let jobDeleteEndpoint: JobDeleteEndpoint
    private let jobResultsEndpoint: JobResultsEndpoint
    private let jobResultsProvider: JobResultsProvider
    private let jobStateEndpoint: JobStateEndpoint
    private let jobStateProvider: JobStateProvider
    private let kickstartWorkerEndpoint: KickstartWorkerEndpoint
    private let queueServerVersionHandler: QueueServerVersionEndpoint
    private let runningQueueStateProvider: RunningQueueStateProvider
    private let scheduleTestsHandler: ScheduleTestsEndpoint
    private let stuckBucketsPoller: StuckBucketsPoller
    private let testsEnqueuer: TestsEnqueuer
    private let toggleWorkersSharingEndpoint: ToggleWorkersSharingEndpoint
    private let workerAlivenessMetricCapturer: WorkerAlivenessMetricCapturer
    private let workerAlivenessPoller: WorkerAlivenessPoller
    private let workerAlivenessProvider: WorkerAlivenessProvider
    private let workerRegistrar: WorkerRegistrar
    private let workerStatusEndpoint: WorkerStatusEndpoint
    private let workersToUtilizeEndpoint: WorkersToUtilizeEndpoint
    
    public init(
        automaticTerminationController: AutomaticTerminationController,
        bucketSplitInfo: BucketSplitInfo,
        checkAgainTimeInterval: TimeInterval,
        dateProvider: DateProvider,
        deploymentDestinations: [DeploymentDestination],
        emceeVersion: Version,
        localPortDeterminer: LocalPortDeterminer,
        onDemandWorkerStarter: OnDemandWorkerStarter,
        payloadSignature: PayloadSignature,
        queueServerLock: QueueServerLock,
        requestSenderProvider: RequestSenderProvider,
        uniqueIdentifierGenerator: UniqueIdentifierGenerator,
        workerAlivenessProvider: WorkerAlivenessProvider,
        workerCapabilitiesStorage: WorkerCapabilitiesStorage,
        workerConfigurations: WorkerConfigurations,
        workerUtilizationStatusPoller: WorkerUtilizationStatusPoller,
        workersToUtilizeService: WorkersToUtilizeService
    ) {
        self.httpRestServer = HTTPRESTServer(
            automaticTerminationController: automaticTerminationController,
            portProvider: localPortDeterminer
        )
        
        let alivenessPollingInterval: TimeInterval = 20
        let workerDetailsHolder = WorkerDetailsHolderImpl()
        
        self.workerAlivenessProvider = workerAlivenessProvider
        self.workerAlivenessPoller = WorkerAlivenessPoller(
            pollInterval: alivenessPollingInterval,
            requestSenderProvider: requestSenderProvider,
            workerAlivenessProvider: workerAlivenessProvider,
            workerDetailsHolder: workerDetailsHolder
        )
        
        let bucketQueueFactory = BucketQueueFactoryImpl(
            checkAgainTimeInterval: checkAgainTimeInterval,
            dateProvider: dateProvider,
            testHistoryTracker: TestHistoryTrackerImpl(
                testHistoryStorage: TestHistoryStorageImpl(),
                uniqueIdentifierGenerator: uniqueIdentifierGenerator
            ),
            uniqueIdentifierGenerator: uniqueIdentifierGenerator,
            workerAlivenessProvider: workerAlivenessProvider,
            workerCapabilitiesStorage: workerCapabilitiesStorage
        )
        let nothingToDequeueBehavior: NothingToDequeueBehavior = NothingToDequeueBehaviorCheckLater(
            checkAfter: checkAgainTimeInterval
        )
        
        let multipleQueuesContainer = MultipleQueuesContainer()
        let jobManipulator: JobManipulator = MultipleQueuesJobManipulator(
            multipleQueuesContainer: multipleQueuesContainer
        )
        self.jobStateProvider = MultipleQueuesJobStateProvider(
            multipleQueuesContainer: multipleQueuesContainer
        )
        self.jobResultsProvider = MultipleQueuesJobResultsProvider(
            multipleQueuesContainer: multipleQueuesContainer
        )
        let enqueueableBucketReceptor: EnqueueableBucketReceptor = MultipleQueuesEnqueueableBucketReceptor(
            bucketQueueFactory: bucketQueueFactory,
            multipleQueuesContainer: multipleQueuesContainer
        )
        self.runningQueueStateProvider = MultipleQueuesRunningQueueStateProvider(
            multipleQueuesContainer: multipleQueuesContainer
        )
        
        let dequeueableBucketSource: DequeueableBucketSource = DequeueableBucketSourceWithMetricSupport(
            dateProvider: dateProvider,
            dequeueableBucketSource: WorkerPermissionAwareDequeueableBucketSource(
                dequeueableBucketSource: MultipleQueuesDequeueableBucketSource(
                    multipleQueuesContainer: multipleQueuesContainer,
                    nothingToDequeueBehavior: nothingToDequeueBehavior
                ),
                nothingToDequeueBehavior: nothingToDequeueBehavior,
                workerPermissionProvider: workerUtilizationStatusPoller
            ),
            jobStateProvider: jobStateProvider,
            queueStateProvider: runningQueueStateProvider,
            version: emceeVersion
        )
        let bucketResultAccepter: BucketResultAccepter = MultipleQueuesBucketResultAccepter(
            multipleQueuesContainer: multipleQueuesContainer
        )
        let stuckBucketsReenqueuer: StuckBucketsReenqueuer = MultipleQueuesStuckBucketsReenqueuer(
            multipleQueuesContainer: multipleQueuesContainer
        )
        
        self.testsEnqueuer = TestsEnqueuer(
            bucketSplitInfo: bucketSplitInfo,
            dateProvider: dateProvider,
            enqueueableBucketReceptor: enqueueableBucketReceptor,
            version: emceeVersion
        )
        self.scheduleTestsHandler = ScheduleTestsEndpoint(
            testsEnqueuer: testsEnqueuer,
            uniqueIdentifierGenerator: uniqueIdentifierGenerator
        )
        self.workerRegistrar = WorkerRegistrar(
            workerAlivenessProvider: workerAlivenessProvider,
            workerCapabilitiesStorage: workerCapabilitiesStorage,
            workerConfigurations: workerConfigurations,
            workerDetailsHolder: workerDetailsHolder
        )
        self.stuckBucketsPoller = StuckBucketsPoller(
            dateProvider: dateProvider,
            jobStateProvider: jobStateProvider,
            runningQueueStateProvider: runningQueueStateProvider,
            stuckBucketsReenqueuer: stuckBucketsReenqueuer,
            version: emceeVersion
        )
        self.bucketProvider = BucketProviderEndpoint(
            dequeueableBucketSource: dequeueableBucketSource,
            expectedPayloadSignature: payloadSignature
        )
        self.bucketResultRegistrar = BucketResultRegistrar(
            bucketResultAccepter: BucketResultAccepterWithMetricSupport(
                bucketResultAccepter: bucketResultAccepter,
                dateProvider: dateProvider,
                jobStateProvider: jobStateProvider,
                queueStateProvider: runningQueueStateProvider,
                version: emceeVersion
            ),
            expectedPayloadSignature: payloadSignature,
            workerAlivenessProvider: workerAlivenessProvider
        )
        self.kickstartWorkerEndpoint = KickstartWorkerEndpoint(
            onDemandWorkerStarter: onDemandWorkerStarter,
            workerAlivenessProvider: workerAlivenessProvider,
            workerConfigurations: workerConfigurations
        )
        self.disableWorkerHandler = DisableWorkerEndpoint(
            workerAlivenessProvider: workerAlivenessProvider,
            workerConfigurations: workerConfigurations
        )
        self.enableWorkerHandler = EnableWorkerEndpoint(
            workerAlivenessProvider: workerAlivenessProvider,
            workerConfigurations: workerConfigurations
        )
        self.workerStatusEndpoint = WorkerStatusEndpoint(
            workerAlivenessProvider: workerAlivenessProvider
        )
        self.queueServerVersionHandler = QueueServerVersionEndpoint(
            emceeVersion: emceeVersion,
            queueServerLock: queueServerLock
        )
        self.jobResultsEndpoint = JobResultsEndpoint(
            jobResultsProvider: jobResultsProvider
        )
        self.jobStateEndpoint = JobStateEndpoint(
            stateProvider: jobStateProvider
        )
        self.jobDeleteEndpoint = JobDeleteEndpoint(
            jobManipulator: jobManipulator
        )
        self.workerAlivenessMetricCapturer = WorkerAlivenessMetricCapturer(
            dateProvider: dateProvider,
            reportInterval: .seconds(30),
            version: emceeVersion,
            workerAlivenessProvider: workerAlivenessProvider
        )
        self.workersToUtilizeEndpoint = WorkersToUtilizeEndpoint(
            service: workersToUtilizeService
        )
        self.deploymentDestinationsHandler = DeploymentDestinationsEndpoint(destinations: deploymentDestinations)
        self.toggleWorkersSharingEndpoint = ToggleWorkersSharingEndpoint(poller: workerUtilizationStatusPoller)
    }
    
    public func start() throws -> SocketModels.Port {
        httpRestServer.add(handler: RESTEndpointOf(bucketProvider))
        httpRestServer.add(handler: RESTEndpointOf(bucketResultRegistrar))
        httpRestServer.add(handler: RESTEndpointOf(deploymentDestinationsHandler))
        httpRestServer.add(handler: RESTEndpointOf(disableWorkerHandler))
        httpRestServer.add(handler: RESTEndpointOf(enableWorkerHandler))
        httpRestServer.add(handler: RESTEndpointOf(jobDeleteEndpoint))
        httpRestServer.add(handler: RESTEndpointOf(jobResultsEndpoint))
        httpRestServer.add(handler: RESTEndpointOf(jobStateEndpoint))
        httpRestServer.add(handler: RESTEndpointOf(kickstartWorkerEndpoint))
        httpRestServer.add(handler: RESTEndpointOf(queueServerVersionHandler))
        httpRestServer.add(handler: RESTEndpointOf(scheduleTestsHandler))
        httpRestServer.add(handler: RESTEndpointOf(toggleWorkersSharingEndpoint))
        httpRestServer.add(handler: RESTEndpointOf(workerRegistrar))
        httpRestServer.add(handler: RESTEndpointOf(workerStatusEndpoint))
        httpRestServer.add(handler: RESTEndpointOf(workersToUtilizeEndpoint))

        stuckBucketsPoller.startTrackingStuckBuckets()
        workerAlivenessMetricCapturer.start()
        workerAlivenessPoller.startPolling()
        
        let port = try httpRestServer.start()
        Logger.info("Started queue server on port \(port)")
        
        return port
    }
    
    public func schedule(
        bucketSplitter: BucketSplitter,
        testEntryConfigurations: [TestEntryConfiguration],
        prioritizedJob: PrioritizedJob
    ) throws {
        try testsEnqueuer.enqueue(
            bucketSplitter: bucketSplitter,
            testEntryConfigurations: testEntryConfigurations,
            prioritizedJob: prioritizedJob
        )
    }
    
    public var isDepleted: Bool {
        return runningQueueStateProvider.runningQueueState.isDepleted
    }
    
    public var hasAnyAliveWorker: Bool {
        return workerAlivenessProvider.hasAnyAliveWorker
    }
    
    public var ongoingJobIds: Set<JobId> {
        return jobStateProvider.ongoingJobIds
    }
    
    public func queueResults(jobId: JobId) throws -> JobResults {
        return try jobResultsProvider.results(jobId: jobId)
    }
    
    public var queueServerPortProvider: QueueServerPortProvider {
        httpRestServer
    }
}

extension HTTPRESTServer: QueueServerPortProvider {}
