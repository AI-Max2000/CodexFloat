import Foundation

public enum CodexExecutableLocator {
  public static func locate(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL? {
    let home = fileManager.homeDirectoryForCurrentUser
    var candidates = [
      URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
      home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
      URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
      URL(fileURLWithPath: "/usr/local/bin/codex"),
    ]
    if let path = environment["PATH"] {
      candidates.append(
        contentsOf: path.split(separator: ":").map {
          URL(fileURLWithPath: String($0)).appendingPathComponent("codex")
        })
    }
    return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
  }
}
