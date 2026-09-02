import AppKit
import CodexQuotaCore
import SwiftUI
import Testing

@testable import CodexFloat

@Suite("Configurable minimal meters")
struct MinimalMeterTests {
  @Test func defaultKeepsExistingVerticalCanvas() {
    let value = MinimalMeterAppearance()
    #expect(value.style == .vertical)
    #expect(value.contentSize == NSSize(width: 26, height: 44))
    #expect(value.collapsedSize == NSSize(width: 36, height: 54))
  }

  @Test @MainActor func settingsPersistEachStyleIndependentlyAndRecoverFromInvalidData() throws {
    let suite = "MinimalSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    #expect(settings.minimalMeterAppearance == MinimalMeterAppearance())
    settings.minimalMeterAppearance.dimensions = .init(length: 90, thickness: 10, scale: 1.5)
    settings.minimalMeterAppearance.style = .ring
    settings.minimalMeterAppearance.dimensions = .init(length: 56, thickness: 5, scale: 1.25)
    settings.minimalMeterAppearance.style = .horizontal
    settings.minimalMeterAppearance.dimensions = .init(length: 120, thickness: 8, scale: 0.8)
    let restored = AppSettings(defaults: defaults)
    #expect(restored.minimalMeterAppearance == settings.minimalMeterAppearance)
    restored.minimalMeterAppearance.dimensions = .defaults(for: .horizontal)
    #expect(
      restored.minimalMeterAppearance.vertical == .init(length: 90, thickness: 10, scale: 1.5))
    #expect(restored.minimalMeterAppearance.ring == .init(length: 56, thickness: 5, scale: 1.25))
    defaults.set(Data("broken-json".utf8), forKey: "minimalMeterAppearanceV1")
    #expect(AppSettings(defaults: defaults).minimalMeterAppearance == MinimalMeterAppearance())
    settings.minimalMeterAppearance.vertical = .init(
      length: .nan, thickness: .infinity, scale: -.infinity)
    #expect(settings.minimalMeterAppearance.vertical == .defaults(for: .vertical))
    #expect(
      AppSettings(defaults: defaults).minimalMeterAppearance == settings.minimalMeterAppearance)
  }

  @Test func allSizesAreBoundedAndDualRingsNeverOverlap() {
    for style in MinimalMeterStyle.allCases {
      for length in [-1.0, 20, 38, 80, 160, 9999] {
        for thickness in [-1.0, 2, 6, 12, 999] {
          for scale in [-1.0, 0.5, 1, 2, 999] {
            var appearance = MinimalMeterAppearance(style: style)
            appearance.dimensions = .init(length: length, thickness: thickness, scale: scale)
            appearance = appearance.normalized
            let size = appearance.collapsedSize
            #expect(size.width >= 36 && size.width <= 366)
            #expect(size.height >= 36 && size.height <= 342)
            #expect(appearance.contentSize.width <= size.width - 10)
            #expect(appearance.contentSize.height <= size.height - 10)
            if style == .ring {
              let dimensions = appearance.dimensions
              let innerDiameter = dimensions.length - 3 * dimensions.thickness
              #expect(innerDiameter > 2 * dimensions.thickness)
            }
          }
        }
      }
    }
  }

  @Test func ringDistinguishesUnknownZeroAndFull() {
    #expect(MinimalRingQuotaView.fraction(nil) == nil)
    #expect(MinimalRingQuotaView.fraction(.nan) == nil)
    #expect(MinimalRingQuotaView.fraction(0) == 0)
    #expect(MinimalRingQuotaView.fraction(-10) == 0)
    #expect(MinimalRingQuotaView.fraction(72) == 0.72)
    #expect(MinimalRingQuotaView.fraction(100) == 1)
    #expect(MinimalRingQuotaView.fraction(200) == 1)
  }

  @Test func customSeedsStayAttachedAtEveryScreenCorner() {
    let screen = NSRect(x: -1440, y: -400, width: 1440, height: 900)
    for style in MinimalMeterStyle.allCases {
      for scale in [0.5, 1, 2] {
        var appearance = MinimalMeterAppearance(style: style)
        appearance.dimensions.scale = scale
        for right in [false, true] {
          for bottom in [false, true] {
            let size = appearance.collapsedSize
            let compact = NSRect(
              x: right ? screen.maxX - size.width : screen.minX,
              y: bottom ? screen.minY : screen.maxY - size.height,
              width: size.width, height: size.height)
            let expanded = PanelExpansionGeometry.resolve(
              compactFrame: compact, preferredSize: NSSize(width: 340, height: 300),
              visibleFrame: screen)
            #expect(screen.contains(expanded.frame))
            #expect(
              PanelExpansionGeometry.compactFrame(
                in: expanded.frame, size: size, direction: expanded.direction) == compact)
            #expect(
              FloatingPanelLayout.liquidSurfaceSeedSize(
                canvasSize: expanded.frame.size, mode: .minimal, minimalSize: size) == size)
          }
        }
      }
    }
  }
}

extension FloatingPanelLayoutTests {
  @Test @MainActor func customMinimalSizeKeepsAnchorThroughResizeRelaunchAndModeChanges()
    async throws
  {
    try await withEdgePanelFixture(mode: .minimal) {
      controller, settings, defaults, placement, model in
      // Away from an edge, edits keep the exact top-left; at an edge, only
      // clamp the compact entry and persist the resulting position.
      controller.handleMinimalDrag(translation: CGSize(width: -250, height: -250), ended: true)
      let initial = controller.panel.frame
      for style in MinimalMeterStyle.allCases {
        settings.minimalMeterAppearance.style = style
        settings.minimalMeterAppearance.dimensions = .init(length: 60, thickness: 5, scale: 1.5)
        try await Task.sleep(for: .milliseconds(60))
        #expect(controller.panel.frame.size == settings.minimalMeterAppearance.collapsedSize)
        #expect(controller.panel.frame.minX == initial.minX)
        #expect(controller.panel.frame.maxY == initial.maxY)
        let before = controller.panel.frame
        settings.showFiveHourQuota.toggle()
        try await Task.sleep(for: .milliseconds(40))
        #expect(controller.panel.frame == before)
        controller.setCollapsed(false, animated: false)
        settings.minimalMeterAppearance.dimensions.scale = 1.8
        try await Task.sleep(for: .milliseconds(40))
        #expect(controller.compactAnchorFrame.minX == initial.minX)
        #expect(controller.compactAnchorFrame.maxY == initial.maxY)
        controller.setCollapsed(true, animated: false)
        #expect(controller.panel.frame.size == settings.minimalMeterAppearance.collapsedSize)
      }
      let final = controller.panel.frame
      // Mode switching flushes the pending user-size placement immediately.
      settings.quotaDisplayMode = .standard
      try await Task.sleep(for: .milliseconds(40))
      let standard = controller.panel.frame
      settings.minimalMeterAppearance.ring.thickness = 6
      try await Task.sleep(for: .milliseconds(40))
      #expect(controller.panel.frame == standard)
      settings.quotaDisplayMode = .minimal
      try await Task.sleep(for: .milliseconds(40))
      #expect(controller.panel.frame == final)
      let relaunched = FloatingPanelController(
        model: model, placement: placement, panelStateDefaults: defaults,
        reduceMotionProvider: { true })
      defer { relaunched.hide() }
      #expect(relaunched.panel.frame == final)
    }
  }

  @Test @MainActor func sizeChangesDuringMotionAreDeferredAndReversalKeepsSeed() async throws {
    try await withEdgePanelFixture(mode: .minimal) { controller, settings, _, _, _ in
      let initial = controller.compactAnchorFrame
      controller.setCollapsed(false, animated: true)
      settings.minimalMeterAppearance.style = .ring
      settings.minimalMeterAppearance.ring.length = 60
      try await Task.sleep(for: .milliseconds(70))
      #expect(controller.compactAnchorFrame == initial)
      controller.setCollapsed(true, animated: true)
      try await Task.sleep(for: .milliseconds(50))
      #expect(controller.compactAnchorFrame == initial)
      controller.setCollapsed(false, animated: true)
      try await Task.sleep(for: .milliseconds(30))
      #expect(controller.compactAnchorFrame == initial)
      // The queued setting is applied only after the endpoint is reached.
      try await Task.sleep(for: .milliseconds(500))
      #expect(!controller.isSurfaceTransitionInFlight)
      #expect(controller.compactAnchorFrame.size == settings.minimalMeterAppearance.collapsedSize)
      controller.setCollapsed(true, animated: false)
      let resized = controller.panel.frame
      settings.followCodexWindow = true
      try await Task.sleep(for: .milliseconds(40))
      let host = TrackedCodexWindow(id: 33, processID: 100, frame: NSScreen.main!.visibleFrame)
      controller.updateCodexWindow(host)
      settings.minimalMeterAppearance.ring.scale = 0.5
      try await Task.sleep(for: .milliseconds(40))
      let smaller = controller.panel.frame
      #expect(smaller.minX == resized.minX && smaller.maxY == resized.maxY)
      controller.updateCodexWindow(host)
      #expect(controller.panel.frame == smaller)
    }
  }

  @Test @MainActor func newMinimalStylesMatchNativeMotionEndpoints() async throws {
    for style in MinimalMeterStyle.allCases {
      var appearance = MinimalMeterAppearance(style: style)
      appearance.dimensions.scale = 1.5
      try await withEdgePanelFixture(mode: .minimal, appearance: appearance) {
        controller, settings, _, _, _ in
        settings.showFiveHourQuota = true
        // Enabling dual quotas animates the ring's outer value from weekly
        // to 5-hour. Test the hover handoff after that independent fill settles.
        try await Task.sleep(for: .milliseconds(650))
        for dark in [false, true] {
          controller.panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
          try await Task.sleep(for: .milliseconds(60))
          let compact = controller.panel.frame
          let before = try edgePanelImage(controller)
          let beforePixels = try edgePixels(before)
          controller.setCollapsed(false, animated: true)
          let first = try edgePanelImage(controller)
          let seed = try #require(
            first.cropping(
              to: CGRect(
                x: first.width - before.width, y: first.height - before.height, width: before.width,
                height: before.height)))
          let difference = zip(try edgePixels(seed), beforePixels).map { abs(Int($0) - Int($1)) }
          // Fixed geometries must match; allow only small compositing rounding.
          #expect((difference.max() ?? 0) <= 4)
          #expect(difference.filter { $0 > 0 }.count < 50)
          try await assertEdgeTransition(controller, compact: compact)
          controller.setCollapsed(true, animated: true)
          try await assertEdgeTransition(controller, compact: compact)
          let returnedPixels = try edgePixels(edgePanelImage(controller))
          #expect(returnedPixels == beforePixels, "Resting pixels: \(style), dark=\(dark)")
        }
      }
    }
  }

  @Test @MainActor func minimalStylesNativePreview() async throws {
    guard let path = ProcessInfo.processInfo.environment["CODEX_FLOAT_MINIMAL_PREVIEW_DIR"] else {
      return
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try await withEdgePanelFixture(mode: .minimal) { _, settings, _, _, model in
      settings.showFiveHourQuota = true
      for dark in [false, true] {
        try await captureMinimalView(
          MinimalMeterGallery(model: model), size: NSSize(width: 720, height: 460), dark: dark,
          url: directory.appendingPathComponent("gallery-\(dark ? "dark" : "light").png"))
        for language in AppLanguage.allCases {
          settings.appLanguage = language
          for style in MinimalMeterStyle.allCases {
            settings.minimalMeterAppearance.style = style
            try await captureMinimalView(
              VStack(alignment: .leading, spacing: 14) {
                MinimalAppearanceSettingsView(model: model, settings: settings)
              }.padding(20).frame(width: 500).background(Color(nsColor: .windowBackgroundColor)),
              size: NSSize(width: 500, height: 410), dark: dark,
              url: directory.appendingPathComponent(
                "settings-\(language.rawValue)-\(style)-\(dark).png"))
          }
        }
      }
    }
  }
}

@MainActor private struct MinimalMeterGallery: View {
  let model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("极简额度 · 原生渲染测试（示例数据）").font(.headline)
      Text("灰色是总量轨道，彩色是剩余；双额度按 5 小时 / 周分开。").font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 20) {
        ForEach(MinimalMeterStyle.allCases) { style in
          VStack(spacing: 16) {
            Text(AppStrings(language: .simplifiedChinese).text(style.titleKey)).font(.subheadline)
            ForEach([false, true], id: \.self) { dual in
              MinimalQuotaPresentation(
                appearance: MinimalMeterAppearance(style: style),
                entries: QuotaDisplayPolicy(snapshot: model.quota, showFiveHour: dual).compact,
                lowThreshold: 20, criticalThreshold: 5, freshness: .fresh,
                language: .simplifiedChinese
              )
              .frame(width: 180, height: 64)
            }
            Text("下方：自定义尺寸（150%）").font(.caption2).foregroundStyle(.secondary)
            let custom = customAppearance(style)
            MinimalQuotaPresentation(
              appearance: custom,
              entries: QuotaDisplayPolicy(snapshot: model.quota, showFiveHour: true).compact,
              lowThreshold: 20, criticalThreshold: 5, freshness: .fresh,
              language: .simplifiedChinese
            )
            .frame(width: 180, height: 148)
          }.frame(maxWidth: .infinity)
        }
      }
    }
    .padding(24).frame(width: 720, height: 460)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func customAppearance(_ style: MinimalMeterStyle) -> MinimalMeterAppearance {
    var result = MinimalMeterAppearance(style: style)
    result.dimensions = .init(length: 60, thickness: 6, scale: 1.5)
    return result
  }
}

@MainActor private func captureMinimalView<Content: View>(
  _ content: Content, size: NSSize, dark: Bool, url: URL
) async throws {
  let hosting = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
    defer: false)
  window.isReleasedWhenClosed = false
  window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
  hosting.sizingOptions = []
  window.contentView = hosting
  window.setFrame(NSRect(origin: .zero, size: size), display: true)
  window.orderFrontRegardless()
  defer { window.orderOut(nil) }
  try await Task.sleep(for: .milliseconds(100))
  hosting.layoutSubtreeIfNeeded()
  let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
  hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
  let data = try #require(bitmap.representation(using: .png, properties: [:]))
  try data.write(to: url)
}
