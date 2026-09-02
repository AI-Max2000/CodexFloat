import ActivityClassifier
import CodexQuotaCore
import Foundation

public struct FeedRefreshResult: Sendable {
  public let posts: [FeedPost]
  public let assessments: [ActivityAssessment]
  public let sourceName: String
  public let fetchedAt: Date

  public init(
    posts: [FeedPost], assessments: [ActivityAssessment], sourceName: String, fetchedAt: Date
  ) {
    self.posts = posts
    self.assessments = assessments
    self.sourceName = sourceName
    self.fetchedAt = fetchedAt
  }
}

public actor TiboFeedMonitor {
  private let source: any FeedSource
  private let classifier: RuleBasedActivityClassifier
  private var failureCount = 0

  public init(
    source: any FeedSource = FallbackFeedSource(), classifier: RuleBasedActivityClassifier = .init()
  ) {
    self.source = source
    self.classifier = classifier
  }

  public func refresh() async throws -> FeedRefreshResult {
    do {
      let posts = try await source.fetch()
        .sorted { ($0.postedAt ?? .distantPast) > ($1.postedAt ?? .distantPast) }
      failureCount = 0
      return FeedRefreshResult(
        posts: Array(posts.prefix(100)),
        assessments: posts.prefix(100).map(classifier.classify),
        sourceName: posts.first?.source ?? source.name,
        fetchedAt: Date()
      )
    } catch {
      failureCount += 1
      throw error
    }
  }

  public func nextPollInterval() -> TimeInterval {
    switch failureCount {
    case 0, 1: 5 * 60
    case 2: 15 * 60
    default: 30 * 60
    }
  }
}
