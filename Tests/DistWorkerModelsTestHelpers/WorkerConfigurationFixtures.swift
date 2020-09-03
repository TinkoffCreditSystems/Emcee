import DistWorkerModels
import Foundation
import LoggingSetup
import QueueModels

public final class WorkerConfigurationFixtures {
    public static let workerConfiguration = WorkerConfiguration(
        analyticsConfiguration: AnalyticsConfiguration(
            graphiteConfiguration: nil,
            statsdConfiguration: nil,
            sentryConfiguration: nil
        ),
        numberOfSimulators: 2,
        payloadSignature: PayloadSignature(value: "payloadSignature")
    )
}
