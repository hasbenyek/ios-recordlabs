import XCTest

final class LaunchScreenConfigurationTests: XCTestCase {
    func testSourceInfoPlistContainsLaunchStoryboardConfiguration() throws {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceRoot = testDirectory.deletingLastPathComponent()
        let plist = try String(contentsOf: sourceRoot.appendingPathComponent("RecordLabsiOS/Info.plist"), encoding: .utf8)
        XCTAssertTrue(plist.contains("UILaunchStoryboardName"))
        XCTAssertTrue(plist.contains("LaunchScreen"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("RecordLabsiOS/LaunchScreen.storyboard").path))
    }
}
