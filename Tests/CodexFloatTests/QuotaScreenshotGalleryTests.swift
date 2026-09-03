import AppKit
import CodexQuotaCore
import CryptoKit
import Foundation
import LocalStore
import SwiftUI
import Testing

@testable import CodexFloat

// Evidence capture only. No live clients, account files, system notifications,
// production preferences, navigation, or mutations to production UI code.
extension FloatingPanelLayoutTests {
  @Test @MainActor func captureQuotaBoundaryScreenshotGallery() async throws {
    guard let exportPath = ProcessInfo.processInfo.environment["CODEX_FLOAT_BOUNDARY_GALLERY"]
    else {
      return
    }
    let output = URL(fileURLWithPath: exportPath, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let suite = "QuotaScreenshotGallery.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: temporary)
    }
    let store = try SQLiteStore(databaseURL: temporary.appendingPathComponent("fixture.sqlite"))
    let settings = AppSettings(defaults: defaults)
    settings.appLanguage = .simplifiedChinese
    settings.showRecentTasks = false
    settings.feedEnabled = false
    settings.showResetProbability = false
    settings.followCodexWindow = false
    settings.showOnlyWhenChatGPTIsFrontmost = false
    settings.notificationsEnabled = false
    settings.hoverCollapseDelay = 10
    let strings = AppStrings(language: .simplifiedChinese)
    var records: [[String: Any]] = []
    let selected = Set(
      (ProcessInfo.processInfo.environment["CODEX_FLOAT_CAPTURE_CASES"] ?? "")
        .split(separator: ",").map(String.init))
    if !selected.isEmpty,
      let data = try? Data(contentsOf: output.appendingPathComponent("manifest.json")),
      let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let previous = existing["scenarios"] as? [[String: Any]]
    {
      records = previous.filter { !selected.contains($0["id"] as? String ?? "") }
    }

    for scenario in QuotaCaptureScenario.all
    where selected.isEmpty || selected.contains(scenario.id) {
      for dark in [false, true] {
        let now = Date()
        let snapshot = scenario.snapshot(now: now)
        let model = AppModel(store: store, settings: settings, initialQuota: snapshot)
        settings.showFiveHourQuota = scenario.dual
        settings.showSupplementaryGPTQuotas = scenario.supplementary
        #expect(model.quotaRecovery?.kind == scenario.expectedRecovery)
        let theme = dark ? "dark" : "light"
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        let stem = "\(scenario.id)-\(theme)"
        var captures: [[String: Any]] = []
        for (mode, style, label) in [
          (QuotaDisplayMode.standard, MinimalMeterStyle.vertical, "完整额度"),
          (.minimal, .vertical, "极简竖条"),
          (.minimal, .horizontal, "极简横条"),
          (.minimal, .ring, "极简圆环"),
          (.menuBar, .vertical, "菜单栏浮层"),
        ] {
          settings.quotaDisplayMode = mode
          settings.minimalMeterAppearance.style = style
          let controller = FloatingPanelController(
            model: model, placement: PanelPlacementStore(defaults: defaults),
            panelStateDefaults: defaults, reduceMotionProvider: { true })
          controller.panel.isReleasedWhenClosed = false
          controller.panel.appearance = appearance
          controller.panel.orderFrontRegardless()
          defer { controller.panel.close() }
          try await Task.sleep(for: .milliseconds(100))
          let modeID = mode == .minimal ? "minimal-\(style.rawValue)" : mode.rawValue
          let view = try #require(controller.panel.contentView)
          if mode != .menuBar {
            controller.setCollapsed(true, animated: false)
            try await Task.sleep(for: .milliseconds(80))
            captures.append(
              try QuotaCaptureWriter.capture(
                view, to: output, filename: "\(stem)-\(modeID)-compact.png",
                label: label, role: "compact", mode: modeID))
          }
          controller.setCollapsed(false, animated: false)
          try await Task.sleep(for: .milliseconds(180))
          #expect(controller.panel.frame.height >= 104)
          #expect(controller.panel.frame.height < 500)
          captures.append(
            try QuotaCaptureWriter.capture(
              view, to: output, filename: "\(stem)-\(modeID)-expanded.png",
              label: label + " · 展开", role: "expanded", mode: modeID))
        }

        // Same image factories as AppDelegate.updateStatusItem; this is a
        // capture of the production-drawn icon, not a mocked desktop menu bar.
        let display = QuotaDisplayPolicy(snapshot: snapshot, showFiveHour: scenario.dual)
        let menuImage: NSImage
        if let recovery = model.quotaRecovery {
          menuImage = MenuBarRecoveryIndicator.image(
            state: recovery, strings: strings, appearance: appearance)
        } else if display.isDual {
          menuImage = MenuBarDualQuotaIndicator.image(
            entries: display.compact, strings: strings, now: now,
            lowThreshold: settings.lowThreshold, criticalThreshold: settings.criticalThreshold,
            appearance: appearance)
        } else {
          menuImage = MenuBarQuotaIndicator.image(
            remainingPercent: display.compact.first?.window?.remainingPercent,
            countdown: strings.menuBarBadgeCountdown(
              to: display.compact.first?.window?.resetsAt, now: now),
            lowThreshold: settings.lowThreshold, criticalThreshold: settings.criticalThreshold,
            appearance: appearance)
        }
        captures.append(
          try await QuotaCaptureWriter.captureView(
            Image(nsImage: menuImage).padding(4), width: menuImage.size.width + 8,
            appearance: appearance, to: output, filename: "\(stem)-menuBar-compact.png",
            label: "菜单栏图标 · 原生绘图", role: "compact", mode: "menuBar"))

        // Cached snapshots are not a new quota-read event: do not manufacture
        // a current bubble from an old observation before a credit expired.
        if let snapshot, snapshot.freshness == .fresh, !scenario.expiredCredit {
          let previous = RecoveryFixture.snapshot(
            windows: snapshot.windows.map {
              RecoveryFixture.window(
                remaining: 60, id: $0.id, minutes: $0.windowDurationMinutes ?? 10_080,
                resetAt: $0.resetsAt)
            }, count: scenario.resets, observedAt: now.addingTimeInterval(-30))
          if let feedback = AppFeedbackPlanner.quotaFeedback(
            previous: previous, current: snapshot, lowThreshold: settings.lowThreshold,
            criticalThreshold: settings.criticalThreshold, strings: strings)
          {
            captures.append(
              try await QuotaCaptureWriter.captureView(
                FeedbackBannerView(
                  feedback: feedback, language: .simplifiedChinese, isPopover: true
                )
                .padding(8),
                width: 350, appearance: appearance, to: output,
                filename: "\(stem)-feedback.png", label: "应用内气泡 · 阈值变化时",
                role: "feedback", mode: "feedback"))
          }
        }
        var fixture: [String: Any] = [
          "freshness": String(describing: scenario.freshness),
          "recovery": model.quotaRecovery.map { String(describing: $0.kind) } ?? "none",
        ]
        fixture["fiveHourRemaining"] = scenario.fiveHour.map { $0 as Any } ?? NSNull()
        fixture["weeklyRemaining"] = scenario.weekly.map { $0 as Any } ?? NSNull()
        fixture["resetCount"] = scenario.resets.map { $0 as Any } ?? NSNull()
        fixture["availableResets"] = model.availableResetCount.map { $0 as Any } ?? NSNull()
        let record: [String: Any] = [
          "id": scenario.id, "title": scenario.title, "note": scenario.note,
          "theme": theme, "dual": scenario.dual, "captures": captures,
          "fixture": fixture,
        ]
        records.append(record)
        print("Captured \(scenario.id) \(theme): \(captures.count) native images")
      }
    }
    let manifest: [String: Any] = [
      "capturedAt": ISO8601DateFormatter().string(from: Date()),
      "appVersion": ProcessInfo.processInfo.environment["CODEX_FLOAT_CAPTURE_VERSION"]
        ?? "0.2.1-dev · current source fixture",
      "provenance":
        "Current production NSPanel/SwiftUI views with isolated synthetic quota snapshots; not live account data. Menu icons use the production native drawing factories. No OS notification was sent.",
      "scenarios": records.sorted {
        (($0["id"] as? String ?? "") + ($0["theme"] as? String ?? ""))
          < (($1["id"] as? String ?? "") + ($1["theme"] as? String ?? ""))
      },
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appendingPathComponent("manifest.json"))
  }
}

private struct QuotaCaptureScenario {
  let id: String
  let title: String
  let note: String
  var fiveHour: Double? = 60
  var weekly: Double? = 72
  var resets: Int? = 2
  var dual = false
  var freshness = DataFreshness.fresh
  var expiredCredit = false
  var resetDue = false
  var spendLimit = false
  var supplementary = false
  var noData = false
  var expectedRecovery: QuotaRecoveryState.Kind?

  func snapshot(now: Date) -> QuotaSnapshot? {
    guard !noData else { return nil }
    var windows: [RateLimitWindow] = []
    if let fiveHour {
      windows.append(
        RecoveryFixture.window(
          remaining: fiveHour, minutes: 300, resetAt: now.addingTimeInterval(3 * 3_600)))
    }
    if let weekly {
      windows.append(
        RecoveryFixture.window(
          remaining: weekly, id: "codex:secondary", minutes: 10_080,
          resetAt: now.addingTimeInterval(resetDue ? -5 : 5 * 86_400 + 13 * 3_600)))
    }
    if supplementary {
      windows.append(
        RecoveryFixture.window(
          id: "gpt-reserve:primary", resetAt: now.addingTimeInterval(86_400)))
    }
    let old = expiredCredit || freshness != .fresh
    return RecoveryFixture.snapshot(
      windows: windows, count: resets,
      credits: expiredCredit
        ? [RecoveryFixture.credit(expiresAt: now.addingTimeInterval(-60))] : [],
      freshness: freshness, observedAt: old ? now.addingTimeInterval(-120) : now,
      spendLimit: spendLimit)
  }

  static let all: [Self] = [
    .init(id: "01-normal", title: "正常 · 默认只展示周额度", note: "正常剩余量，保持原有绿黄红进度和倒计时。"),
    .init(id: "02-dual", title: "正常 · 开启 5 小时双额度", note: "显示偏好开启后，5 小时与每周独立展示。", dual: true),
    .init(
      id: "03-low", title: "周额度偏低 · 剩余 15%", note: "当前实际：周额度变黄，但 5 小时仍为 60% 时未触发应用内气泡。发现遗漏，尚未修复。",
      weekly: 15),
    .init(
      id: "04-critical", title: "周额度即将用尽 · 剩余 3%",
      note: "当前实际：周额度变红，但 5 小时仍为 60% 时未触发应用内气泡。发现遗漏，尚未修复。", weekly: 3),
    .init(
      id: "05-weekly-reset", title: "周额度耗尽 · 有 2 次重置", note: "唯一的主动手动重置引导条件：周额度为零且有可用次数。",
      weekly: 0, expectedRecovery: .exhausted),
    .init(
      id: "06-five-hidden", title: "5 小时耗尽 · 默认隐藏 5 小时", note: "周额度仍有 80%，不改变原有界面，也不引导手动重置。",
      fiveHour: 0, weekly: 80),
    .init(
      id: "07-five-visible", title: "5 小时耗尽 · 双额度已开启", note: "5 小时显示 0%，每周显示 80%，不增加耗尽卡片。",
      fiveHour: 0, weekly: 80, dual: true),
    .init(
      id: "08-weekly-no-reset", title: "周额度耗尽 · 没有重置次数", note: "保持原样：剩余 0%、倒计时和空进度；原有阈值气泡仍可能出现。",
      weekly: 0, resets: 0),
    .init(
      id: "09-both-reset", title: "两个窗口耗尽 · 有重置次数", note: "按周额度提供重置入口，不把 5 小时写成引导原因。", fiveHour: 0,
      weekly: 0, dual: true, expectedRecovery: .exhausted),
    .init(
      id: "10-both-no-reset", title: "两个窗口耗尽 · 没有重置次数", note: "两个额度均显示 0%，不增加耗尽卡片、警示边框或重置按钮。",
      fiveHour: 0, weekly: 0, resets: 0, dual: true),
    .init(
      id: "11-five-only", title: "只返回 5 小时窗口 · 已耗尽", note: "即使有重置次数也不主动引导手动重置，不制造不存在的周额度。",
      fiveHour: 0, weekly: nil),
    .init(
      id: "12-expired", title: "周额度耗尽 · 重置次数已过期", note: "快照中的最后一次重置随后过期，有效次数归零，回到原有展示。", weekly: 0,
      resets: 1, expiredCredit: true),
    .init(
      id: "13-unknown", title: "周额度耗尽 · 重置次数未知", note: "缺少可用次数证据时保持原样，不把未知当成有次数。", weekly: 0,
      resets: nil),
    .init(
      id: "14-stale", title: "周额度耗尽且有次数 · 数据较旧", note: "先重新确认额度；不根据缓存建议消耗次数。", weekly: 0,
      freshness: .stale, expectedRecovery: .needsRefresh),
    .init(
      id: "15-offline", title: "周额度耗尽且有次数 · 离线", note: "保留缓存、说明需要确认；连接恢复后才能验证真实可用量。", weekly: 0,
      freshness: .offline, expectedRecovery: .needsRefresh),
    .init(
      id: "16-reset-due", title: "周额度刷新时间已到 · 等待确认", note: "不自行把额度改成 100%，也不建议立即使用手动重置。", weekly: 0,
      resetDue: true, expectedRecovery: .awaitingReset),
    .init(
      id: "17-spend-limit", title: "周额度耗尽且有次数 · 支出受限", note: "解释支出限制，只提供查看用量设置，不承诺重置可解除限制。",
      weekly: 0, spendLimit: true, expectedRecovery: .spendLimit),
    .init(
      id: "18-model-only", title: "仅模型专项额度耗尽", note: "Codex 周额度仍有 72%，不冒充全局额度耗尽；此例开启专项展示。",
      supplementary: true),
    .init(
      id: "19-fractional", title: "剩余不足 1% · 尚未耗尽", note: "真实剩余 0.2% 显示为 <1%，不四舍五入成 0% 或触发重置入口。",
      weekly: 0.2),
    .init(
      id: "20-no-data", title: "尚未获得额度数据", note: "这是未读到任何快照的初始状态，不伪造 0%，也不是登录失效错误截图。",
      fiveHour: nil, weekly: nil, resets: nil, noData: true),
    .init(
      id: "21-recovered", title: "额度已恢复", note: "收到真实恢复读数后退出耗尽展示；不是点击跳转后就假定恢复。", fiveHour: 100,
      weekly: 100, resets: 1),
    .init(
      id: "22-stale-no-reset", title: "周额度耗尽无次数 · 缓存较旧", note: "没有可用次数时保持原有陈旧状态，不追加新的恢复卡片。",
      weekly: 0, resets: 0, freshness: .stale),
    .init(
      id: "23-both-low", title: "两种额度均偏低 · 应用内气泡", note: "两种额度均从 60% 降至 15%，当前逻辑实际触发低额度气泡。",
      fiveHour: 15, weekly: 15, dual: true),
    .init(
      id: "24-both-critical", title: "两种额度均即将用尽 · 应用内气泡", note: "两种额度均从 60% 降至 3%，当前逻辑实际触发即将用尽气泡。",
      fiveHour: 3, weekly: 3, dual: true),
  ]
}

@MainActor private enum QuotaCaptureWriter {
  static func capture(
    _ view: NSView, to output: URL, filename: String,
    label: String, role: String, mode: String
  ) throws -> [String: Any] {
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: output.appendingPathComponent(filename))
    return [
      "file": filename, "label": label, "role": role, "mode": mode,
      "width": view.bounds.width, "height": view.bounds.height,
      "pixelWidth": bitmap.pixelsWide, "pixelHeight": bitmap.pixelsHigh,
      "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
    ]
  }

  static func captureView<V: View>(
    _ content: V, width: CGFloat, appearance: NSAppearance,
    to output: URL, filename: String, label: String, role: String, mode: String
  ) async throws -> [String: Any] {
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let host = NSHostingView(
      rootView:
        content
        .frame(width: width).fixedSize(horizontal: false, vertical: true)
        // The native popover backs translucent banner ink with an app surface.
        .background(role == "feedback" ? Color(nsColor: .windowBackgroundColor) : Color.clear)
        .environment(\.colorScheme, dark ? .dark : .light))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: host.fittingSize),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = appearance
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.close() }
    try await Task.sleep(for: .milliseconds(80))
    return try capture(host, to: output, filename: filename, label: label, role: role, mode: mode)
  }
}
