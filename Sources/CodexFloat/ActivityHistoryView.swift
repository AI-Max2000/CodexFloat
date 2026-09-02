import AppKit
import CodexQuotaCore
import SwiftUI

struct ActivityHistoryView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var settings: AppSettings

  private var strings: AppStrings { AppStrings(language: settings.appLanguage) }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(strings.text(.activityHistoryTitle)).font(.title2.weight(.semibold))
          Text(sourceStatus)
            .font(.caption)
            .foregroundStyle(model.feedError == nil ? Color.secondary : Color.orange)
        }
        Spacer()
        Button {
          model.refreshAll()
        } label: {
          Label(strings.text(.refresh), systemImage: "arrow.clockwise")
        }
        .disabled(model.isRefreshingFeed)
      }
      .padding(16)

      Divider()

      if model.resetAnnouncementPosts.isEmpty {
        ContentUnavailableView(
          strings.text(.noResetAnnouncements),
          systemImage: "dot.radiowaves.left.and.right",
          description: Text(model.feedError ?? strings.text(.unrelatedPostsHidden))
        )
      } else {
        List(model.resetAnnouncementPosts) { post in
          if let assessment = model.assessment(for: post) {
            activityRow(post: post, assessment: assessment)
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(minWidth: 680, minHeight: 520)
    .environment(\.locale, settings.appLanguage.locale)
  }

  private func activityRow(post: FeedPost, assessment: ActivityAssessment) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Label(strings.activityType(assessment.type), systemImage: icon(assessment.type))
          .font(.caption.weight(.semibold))
        Text(strings.verification(assessment.verification))
          .font(.caption2.weight(.semibold))
          .foregroundStyle(verificationColor(assessment.verification))
        Text(strings.format(.confidence, Int((assessment.confidence * 100).rounded())))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        Text(post.postedAt.map(strings.shortDateTime) ?? strings.text(.timeUnknown))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Text(strings.activitySummary(assessment))
        .font(.body.weight(.medium))

      Label(expectedResetLabel(assessment), systemImage: "clock")
        .font(.callout.weight(.semibold))

      Text(post.text)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(3)

      HStack(spacing: 12) {
        Text(strings.format(.audience, strings.audience(assessment.audience)))
        Text(
          assessment.requiresAction
            ? strings.text(.actionRequired) : strings.text(.noActionOrPending)
        )
        Text(strings.format(.evidence, strings.evidence(assessment.evidence)))
          .lineLimit(1)
        Spacer()
        Button(strings.text(.viewOriginalPost)) { NSWorkspace.shared.open(post.originalURL) }
          .buttonStyle(.link)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
  }

  private var sourceStatus: String {
    if let error = model.feedError { return error }
    let source = model.feedSourceName ?? strings.text(.waitingForSource)
    let time = model.feedFetchedAt.map(strings.timeWithSeconds) ?? strings.text(.notUpdated)
    return strings.format(.sourceStatus, source, time)
  }

  private func icon(_ type: ActivityType) -> String {
    switch type {
    case .globalReset: "arrow.counterclockwise.circle"
    case .bankedReset: "banknote"
    case .conditionalReset: "checklist"
    case .limitChange: "slider.horizontal.3"
    case .plannedActivity: "calendar.badge.clock"
    case .incidentOrFix: "wrench.and.screwdriver"
    case .other: "text.bubble"
    }
  }

  private func verificationColor(_ state: VerificationState) -> Color {
    switch state {
    case .observed: .green
    case .unverified: .orange
    case .announced: .secondary
    case .expired: .gray
    }
  }

  private func expectedResetLabel(_ assessment: ActivityAssessment) -> String {
    let value = strings.expectedResetTime(assessment)
    switch settings.appLanguage {
    case .simplifiedChinese: return "预计重置：\(value)"
    case .traditionalChinese: return "預計重置：\(value)"
    case .english: return "Expected reset: \(value)"
    }
  }

}
