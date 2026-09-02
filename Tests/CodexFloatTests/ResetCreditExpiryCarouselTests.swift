import CodexQuotaCore
import Foundation
import Testing

@testable import CodexFloat

@Suite("Reset credit expiry carousel")
struct ResetCreditExpiryCarouselTests {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)

  @Test func carouselStartsStrictlyInsideSevenDays() {
    #expect(schedule(days: 7) == nil)
    #expect(schedule(days: 7, offset: -1)?.stage == .sevenDays)
    #expect(schedule(days: 5)?.stage == .sevenDays)
    #expect(schedule(days: 5, offset: -1)?.stage == .fiveDays)
    #expect(schedule(days: 3)?.stage == .fiveDays)
    #expect(schedule(days: 3, offset: -1)?.stage == .threeDays)
    #expect(schedule(days: 1)?.stage == .threeDays)
    #expect(schedule(days: 1, offset: -1)?.stage == .oneDay)
    #expect(schedule(days: 0) == nil)
  }

  @Test func expiryShareIncreasesAtEveryUrgencyStage() throws {
    let schedules = try [
      #require(schedule(days: 6)),
      #require(schedule(days: 4)),
      #require(schedule(days: 2)),
      #require(schedule(days: 0.5)),
    ]

    #expect(schedules.allSatisfy {
      $0.countDuration + $0.expiryDuration
        == ResetCreditExpiryCarouselPolicy.cycleDuration
    })
    #expect(zip(schedules, schedules.dropFirst()).allSatisfy {
      $1.expiryDuration > $0.expiryDuration
    })
    #expect(schedules.first?.countDuration == 10)
    #expect(schedules.last?.expiryDuration == 7)
  }

  @Test func earliestExpiryIgnoresConsumedAndAlreadyExpiredCredits() {
    let credits = [
      credit(id: "used", status: "consumed", expiresIn: 0.5),
      credit(id: "past", status: "available", expiresIn: -1),
      credit(id: "later", status: "available", expiresIn: 6),
      credit(id: "earliest", status: "unused", expiresIn: 2),
      credit(id: "no-date", status: nil, expiresIn: nil),
    ]

    #expect(
      ResetCreditExpiryCarouselPolicy.earliestAvailableExpiry(in: credits, now: now)
        == now.addingTimeInterval(2 * ResetCreditExpiryCarouselPolicy.day)
    )
    #expect(ResetCreditExpiryCarouselPolicy.availableCount(in: credits, now: now) == 3)
  }

  private func schedule(days: Double, offset: TimeInterval = 0)
    -> ResetCreditExpiryCarouselPolicy.Schedule?
  {
    ResetCreditExpiryCarouselPolicy.schedule(
      expiresAt: now.addingTimeInterval(days * ResetCreditExpiryCarouselPolicy.day + offset),
      now: now
    )
  }

  private func credit(
    id: String,
    status: String?,
    expiresIn days: Double?
  ) -> ResetCredit {
    ResetCredit(
      id: id,
      resetType: "banked",
      status: status,
      grantedAt: now,
      expiresAt: days.map {
        now.addingTimeInterval($0 * ResetCreditExpiryCarouselPolicy.day)
      },
      title: "Reset",
      detail: nil
    )
  }
}
