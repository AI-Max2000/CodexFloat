import Testing

@testable import CodexFloat

@Suite("Quota meter color transitions")
struct QuotaMeterPaletteTests {
  @Test func accessibilityTitleIdentifiesEachDynamicWindow() {
    #expect(
      QuotaMeterAccessibility.title(
        name: "GPT-5.3-Codex-Spark · 主窗口",
        language: .simplifiedChinese
      ) == "GPT-5.3-Codex-Spark · 主窗口 剩余额度"
    )
    #expect(
      QuotaMeterAccessibility.title(
        name: "GPT-5.3-Codex-Spark · Secondary window",
        language: .english
      ) == "GPT-5.3-Codex-Spark · Secondary window quota remaining"
    )
  }

  @Test func usesGreenYellowAndRedAtStableRanges() {
    #expect(
      QuotaMeterPalette.components(
        remainingPercent: 80, lowThreshold: 20, criticalThreshold: 5)
        == QuotaMeterPalette.normal)
    #expect(
      QuotaMeterPalette.components(
        remainingPercent: 20, lowThreshold: 20, criticalThreshold: 5)
        == QuotaMeterPalette.low)
    #expect(
      QuotaMeterPalette.components(
        remainingPercent: 5, lowThreshold: 20, criticalThreshold: 5)
        == QuotaMeterPalette.critical)
  }

  @Test func blendsBeforeEnteringLowRange() {
    let transition = QuotaMeterPalette.components(
      remainingPercent: 22, lowThreshold: 20, criticalThreshold: 5)

    #expect(transition != QuotaMeterPalette.normal)
    #expect(transition != QuotaMeterPalette.low)
    #expect(transition.red > QuotaMeterPalette.normal.red)
    #expect(transition.blue < QuotaMeterPalette.normal.blue)
  }

  @Test func blendsBeforeEnteringCriticalRange() {
    let transition = QuotaMeterPalette.components(
      remainingPercent: 7, lowThreshold: 20, criticalThreshold: 5)

    #expect(transition != QuotaMeterPalette.low)
    #expect(transition != QuotaMeterPalette.critical)
    #expect(transition.green > QuotaMeterPalette.critical.green)
    #expect(transition.green < QuotaMeterPalette.low.green)
  }
}
