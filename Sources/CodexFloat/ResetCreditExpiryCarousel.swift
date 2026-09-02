import CodexQuotaCore
import SwiftUI

enum ResetCreditExpiryCarouselPolicy {
  static let day: TimeInterval = 86_400
  static let cycleDuration: TimeInterval = 12

  enum Stage: Int, CaseIterable, Equatable, Sendable {
    case sevenDays
    case fiveDays
    case threeDays
    case oneDay
  }

  struct Schedule: Equatable, Sendable {
    let stage: Stage
    let countDuration: TimeInterval
    let expiryDuration: TimeInterval
  }

  static func schedule(expiresAt: Date, now: Date) -> Schedule? {
    let remaining = expiresAt.timeIntervalSince(now)
    guard remaining > 0, remaining < 7 * day else { return nil }

    if remaining < day {
      return Schedule(stage: .oneDay, countDuration: 5, expiryDuration: 7)
    }
    if remaining < 3 * day {
      return Schedule(stage: .threeDays, countDuration: 7, expiryDuration: 5)
    }
    if remaining < 5 * day {
      return Schedule(stage: .fiveDays, countDuration: 8, expiryDuration: 4)
    }
    return Schedule(stage: .sevenDays, countDuration: 10, expiryDuration: 2)
  }

  static func earliestAvailableExpiry(in credits: [ResetCredit], now: Date) -> Date? {
    credits.compactMap { credit in
      guard isAvailable(credit), let expiresAt = credit.expiresAt, expiresAt > now else {
        return nil
      }
      return expiresAt
    }.min()
  }

  static func availableCount(in credits: [ResetCredit], now: Date) -> Int {
    credits.filter { credit in
      guard isAvailable(credit) else { return false }
      return credit.expiresAt.map { $0 > now } ?? true
    }.count
  }

  private static func isAvailable(_ credit: ResetCredit) -> Bool {
    guard let status = credit.status?.lowercased() else { return true }
    return !["used", "consumed", "expired"].contains(status)
  }
}

private enum ResetCreditCarouselPage {
  case count
  case expiry
}

struct ResetCreditExpiryCarouselView: View {
  let count: Int
  let expiresAt: Date?
  let language: AppLanguage

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var page = ResetCreditCarouselPage.count

  private var strings: AppStrings { AppStrings(language: language) }

  var body: some View {
    TimelineView(.periodic(from: .now, by: timelineInterval)) { context in
      let schedule = expiresAt.flatMap {
        ResetCreditExpiryCarouselPolicy.schedule(expiresAt: $0, now: context.date)
      }
      ZStack(alignment: .leading) {
        if page == .expiry, let expiresAt, schedule != nil {
          expiryText(expiresAt: expiresAt, now: context.date)
            .transition(reduceMotion ? .identity : .resetCreditVerticalCarousel)
        } else {
          countText
            .transition(reduceMotion ? .identity : .resetCreditVerticalCarousel)
        }
      }
      .frame(width: 92, height: 16, alignment: .leading)
      .clipped()
      .animation(
        reduceMotion
          ? nil
          : .timingCurve(0.22, 1, 0.36, 1, duration: 0.30),
        value: page
      )
      .task(id: expiresAt) {
        await runCarousel()
      }
    }
    .layoutPriority(2)
  }

  private var countText: some View {
    Text(strings.format(.resetCountHeader, count))
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.mint)
      .lineLimit(1)
      .minimumScaleFactor(0.78)
      .accessibilityLabel(strings.format(.resetCountHeader, count))
  }

  private func expiryText(expiresAt: Date, now: Date) -> some View {
    let remaining = expiresAt.timeIntervalSince(now)
    return Text(strings.format(.resetExpiryCompact, strings.countdown(to: expiresAt, now: now)))
      .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
      .foregroundStyle(remaining < ResetCreditExpiryCarouselPolicy.day ? Color.red : Color.orange)
      .lineLimit(1)
      .minimumScaleFactor(0.76)
      .help(strings.format(.expiresAt, strings.fullDateTime(expiresAt)))
      .accessibilityLabel(strings.format(.expiresAt, strings.fullDateTime(expiresAt)))
  }

  private var timelineInterval: TimeInterval {
    guard let expiresAt else { return 60 }
    return expiresAt.timeIntervalSinceNow < ResetCreditExpiryCarouselPolicy.day ? 1 : 60
  }

  @MainActor
  private func runCarousel() async {
    page = .count
    guard let expiresAt else { return }

    while !Task.isCancelled {
      guard let schedule = ResetCreditExpiryCarouselPolicy.schedule(
        expiresAt: expiresAt,
        now: Date()
      ) else {
        page = .count
        return
      }
      let duration = page == .count ? schedule.countDuration : schedule.expiryDuration
      do {
        try await Task.sleep(for: .seconds(duration))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      page = page == .count ? .expiry : .count
    }
  }
}

private extension AnyTransition {
  static var resetCreditVerticalCarousel: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .bottom),
      removal: .move(edge: .top)
    )
  }
}
