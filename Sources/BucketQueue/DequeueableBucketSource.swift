import Foundation
import QueueModels

public protocol DequeueableBucketSource {
    func previouslyDequeuedBucket(requestId: RequestId, workerId: WorkerId) -> DequeuedBucket?
    func dequeueBucket(requestId: RequestId, workerId: WorkerId) -> DequeueResult
}
