import Foundation
import Models

public final class TestEntryFixtures {
    public static func testEntry(
        className: String = "class",
        methodName: String = "test",
        tags: [String] = [],
        caseId: UInt? = nil)
        -> TestEntry
    {
        return TestEntry(
            className: className,
            methodName: methodName,
            tags: tags,
            caseId: caseId
        )
    }
}
