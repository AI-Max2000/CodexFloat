import Testing

@testable import CodexFloat

@Suite("Settings window layout")
struct SettingsLayoutTests {
  @Test func defaultWindowIsCompactButStillUsable() {
    #expect(SettingsLayout.width == 540)
    #expect(SettingsLayout.height <= 640)
    #expect(SettingsLayout.height >= 520)
  }
}
