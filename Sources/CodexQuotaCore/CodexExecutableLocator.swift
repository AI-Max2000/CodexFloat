import AppKit
import Foundation

public enum CodexExecutableLocator {
  public static func locate(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    applicationURLs: [URL]? = nil
  ) -> URL? {
    let home = fileManager.homeDirectoryForCurrentUser
    // Ask Launch Services first: users may rename or move the desktop app.
    let applications = applicationURLs ?? (
      ["com.openai.codex", "com.openai.chat"].compactMap {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
      } + ["/Applications", home.appendingPathComponent("Applications").path].flatMap { root in
        ["Codex.app", "ChatGPT.app"].map {
          URL(fileURLWithPath: root).appendingPathComponent($0)
        }
      })
    var seen = Set<String>()
    for application in applications where seen.insert(application.standardizedFileURL.path).inserted {
      if let executable = bundledExecutable(in: application, fileManager: fileManager) {
        return executable
      }
    }
    var candidates = applicationURLs == nil ? [
      URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
      URL(fileURLWithPath: "/usr/local/bin/codex"),
    ] : []
    if let path = environment["PATH"] {
      candidates.append(
        contentsOf: path.split(separator: ":").map {
          URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
        })
    }
    return candidates.first { isExecutableFile($0, fileManager: fileManager) }
  }

  private static func bundledExecutable(in application: URL, fileManager: FileManager) -> URL? {
    let resources = application.appendingPathComponent("Contents/Resources")
    // Fast paths avoid a directory walk for known versions.
    for relative in ["codex-cli/CodexCLI.app/Contents/MacOS/codex", "codex"] {
      let candidate = resources.appendingPathComponent(relative)
      if isExecutableFile(candidate, fileManager: fileManager) { return candidate }
    }
    // Bounded discovery inside the installed app only, never a disk-wide search.
    // Do not descend symlink directories into unrelated locations.
    guard let entries = fileManager.enumerator(
      at: resources, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else { return nil }
    var visited = 0
    for case let candidate as URL in entries {
      visited += 1
      guard visited <= 8_000 else { break }
      let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
      if values?.isSymbolicLink == true || entries.level > 8 {
        entries.skipDescendants()
        continue
      }
      if candidate.lastPathComponent == "codex", values?.isRegularFile == true,
        fileManager.isExecutableFile(atPath: candidate.path)
      {
        return candidate
      }
    }
    return nil
  }

  private static func isExecutableFile(_ url: URL, fileManager: FileManager) -> Bool {
    var directory: ObjCBool = false
    return fileManager.fileExists(atPath: url.path, isDirectory: &directory)
      && !directory.boolValue && fileManager.isExecutableFile(atPath: url.path)
  }
}
