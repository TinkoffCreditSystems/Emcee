import Foundation
import QueueModels
import SocketModels

public final class RegisterWorkerPayload: Codable {
    public let workerId: WorkerId
    public let workerRestAddress: SocketAddress
    
    public init(
        workerId: WorkerId,
        workerRestAddress: SocketAddress
    ) {
        self.workerId = workerId
        self.workerRestAddress = workerRestAddress
    }
}
