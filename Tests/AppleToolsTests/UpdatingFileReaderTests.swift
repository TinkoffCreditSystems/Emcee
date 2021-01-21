import AppleTools
import DateProvider
import FileSystem
import Foundation
import PathLib
import ProcessController
import TemporaryStuff
import TestHelpers
import XCTest

final class UpdatingFileReaderTests: XCTestCase {
    lazy var tempFile = assertDoesNotThrow { try TemporaryFile() }
    
    func test() throws {
        let reader = try UpdatingFileReader(
            path: tempFile.absolutePath,
            processControllerProvider: DefaultProcessControllerProvider(
                dateProvider: SystemDateProvider(),
                fileSystem: LocalFileSystem()
            )
        )
        
        let collected = XCTestExpectation()
        
        var collectedContents = ""
        let handler = try reader.read { data in
            guard let string = String(data: data, encoding: .utf8) else { return }
            collectedContents.append(string)
            
            if string.contains("\t") {
                collected.fulfill()
            }
        }
        
        tempFile.fileHandleForWriting.write("hello")
        tempFile.fileHandleForWriting.write(" world")
        tempFile.fileHandleForWriting.write("\n123\n")
        tempFile.fileHandleForWriting.write("\t")
        
        wait(for: [collected], timeout: 15)
        handler.cancel()
        
        XCTAssertEqual(collectedContents, "hello world\n123\n\t")
    }
}
