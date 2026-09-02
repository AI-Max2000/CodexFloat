import Foundation

/// Keeps older Codex Float hook commands harmless without inspecting or editing
/// the user's Codex configuration. Current task monitoring is read-only and uses
/// the local task status index instead of hooks.
enum LegacyTaskHookCompatibility {
  static let argument = "--codex-float-hook"

  static func handle(
    arguments: [String],
    output: FileHandle = .standardOutput
  ) -> Int32? {
    guard arguments.contains(argument) else { return nil }
    output.write(Data("{}\n".utf8))
    return 0
  }
}
