import Foundation
import Testing

@testable import CodexFloat

@Suite("Legacy Codex task hook compatibility")
struct TaskHookTests {
  @Test func legacyHookCommandReturnsAnEmptySuccessResponse() throws {
    let pipe = Pipe()
    let exitCode = LegacyTaskHookCompatibility.handle(
      arguments: ["CodexFloat", LegacyTaskHookCompatibility.argument],
      output: pipe.fileHandleForWriting
    )
    try pipe.fileHandleForWriting.close()

    #expect(exitCode == 0)
    #expect(pipe.fileHandleForReading.readDataToEndOfFile() == Data("{}\n".utf8))
  }

  @Test func normalLaunchDoesNotEnterLegacyCompatibilityMode() {
    #expect(LegacyTaskHookCompatibility.handle(arguments: ["CodexFloat"]) == nil)
  }
}
