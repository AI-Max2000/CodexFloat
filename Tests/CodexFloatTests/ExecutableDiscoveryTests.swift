import Foundation
import Testing

@testable import CodexQuotaCore

@Suite("CLI discovery and recovery")
struct ExecutableDiscoveryTests {
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func executable(_ root: URL, _ relative: String, contents: String = "#!/bin/sh\nexit 0\n") throws -> URL {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }

  @Test(arguments: [
    "Contents/Resources/codex",
    "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
    "Contents/Resources/future-layout/tools/runtime/codex",
  ])
  func discoversOldNewAndUnknownBundleLayouts(relative: String) throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let expected = try executable(root, relative)
    #expect(CodexExecutableLocator.locate(environment: [:], applicationURLs: [root])?.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath())
  }

  @Test func skipsNonExecutableAndFallsBackToPATH() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let invalid = try executable(root, "App.app/Contents/Resources/codex")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: invalid.path)
    let expected = try executable(root, "bin/codex")
    #expect(CodexExecutableLocator.locate(
      environment: ["PATH": root.appendingPathComponent("bin").path],
      applicationURLs: [root.appendingPathComponent("App.app")]) == expected)
  }

  @Test func doesNotSearchOutsideBundleThroughSymlink() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try executable(root, "outside/codex")
    let resources = root.appendingPathComponent("App.app/Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: resources.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("outside"))
    #expect(CodexExecutableLocator.locate(environment: [:], applicationURLs: [root.appendingPathComponent("App.app")]) == nil)
  }

  @Test func sameClientRecoversAfterMissingInstallationAndPathChange() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let client = CodexAppServerClient(executableLocator: {
      CodexExecutableLocator.locate(environment: [:], applicationURLs: [root])
    })
    do {
      _ = try await client.readSnapshot()
      Issue.record("Missing CLI should fail")
    } catch AppServerError.codexNotFound {
      // The same client must recover without recreating the app/model.
    }
    let server = #"""
      #!/bin/sh
      while IFS= read -r line; do
        id=$(printf '%s' "$line" | /usr/bin/sed -E 's/.*"id":([0-9]+).*/\1/')
        case "$line" in
          *'"method":"initialize"'*) printf '{"id":%s,"result":{}}\n' "$id" ;;
          *rateLimits*) printf '{"id":%s,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000}}}}\n' "$id" ;;
        esac
      done
      """#
    do {
      let old = try executable(root, "Contents/Resources/codex", contents: server)
      let first = try await client.readSnapshot()
      #expect(first.windows.first?.remainingPercent == 75)
      await client.stop()
      try FileManager.default.removeItem(at: old)
      _ = try executable(root, "Contents/Resources/new-location/bin/codex", contents: server)
      let second = try await client.readSnapshot()
      #expect(second.windows.first?.remainingPercent == 75)
      await client.stop()
    } catch {
      await client.stop()
      throw error
    }
  }

  @Test func liveQuotaUsingDiscoveredCLI() async throws {
    guard ProcessInfo.processInfo.environment["CODEX_FLOAT_LIVE_QUOTA_TEST"] == "1" else { return }
    let client = CodexAppServerClient()
    do {
      let snapshot = try await client.readSnapshot()
      #expect(!snapshot.windows.isEmpty)
      await client.stop()
    } catch {
      await client.stop()
      throw error
    }
  }
}
