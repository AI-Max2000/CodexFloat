import AppKit

@main
enum CodexFloatMain {
  @MainActor
  static func main() {
    if let exitCode = LegacyTaskHookCompatibility.handle(arguments: CommandLine.arguments) {
      exit(exitCode)
    }
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
      application.run()
    }
  }
}
