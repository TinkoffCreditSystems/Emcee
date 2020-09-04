import BalancingBucketQueue
import BucketQueue
import BucketQueueTestHelpers
import QueueModelsTestHelpers
import Foundation
import XCTest

final class MultipleQueuesStuckBucketsReenqueuerTests: XCTestCase {
    lazy var multipleQueuesContainer = MultipleQueuesContainer()
    lazy var multipleQueuesStuckBucketsReenqueuer = MultipleQueuesStuckBucketsReenqueuer(
        multipleQueuesContainer: multipleQueuesContainer
    )
    
    func test() {
        let stuckBucket = StuckBucket(
            reason: .bucketLost,
            bucket: BucketFixtures.createBucket(),
            workerId: "worker",
            requestId: "request"
        )
        let bucketQueue = FakeBucketQueue(fixedStuckBuckets: [stuckBucket])
        multipleQueuesContainer.add(runningJobQueue: createJobQueue(bucketQueue: bucketQueue))
        
        XCTAssertEqual(
            multipleQueuesStuckBucketsReenqueuer.reenqueueStuckBuckets(),
            [stuckBucket]
        )
    }
}

