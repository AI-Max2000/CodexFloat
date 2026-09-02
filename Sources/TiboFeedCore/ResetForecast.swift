import Foundation

public enum ResetForecastConfidence: String, Codable, Equatable, Sendable {
  case low
  case medium
  case high
  case unavailable
}

public struct ResetMilestoneObservation: Codable, Equatable, Sendable {
  public let usersMillion: Double
  public let announcedAt: Date
  public let group: String?
  public let sourceURL: URL?

  public init(
    usersMillion: Double,
    announcedAt: Date,
    group: String? = nil,
    sourceURL: URL? = nil
  ) {
    self.usersMillion = usersMillion
    self.announcedAt = announcedAt
    self.group = group
    self.sourceURL = sourceURL
  }
}

public struct ResetMilestoneProjection: Codable, Equatable, Sendable {
  public let latestUsersMillion: Double
  public let latestObservedAt: Date
  public let growthMillionPerDay: Double?
  public let nextMillionUsers: Double
  public let nextMillionEstimatedAt: Date?
  public let nextMajorMilestoneUsers: Double
  public let nextMajorMilestoneEstimatedAt: Date?
  public let oneMillionResetPromiseStillApplies: Bool

  public init(
    latestUsersMillion: Double,
    latestObservedAt: Date,
    growthMillionPerDay: Double?,
    nextMillionUsers: Double,
    nextMillionEstimatedAt: Date?,
    nextMajorMilestoneUsers: Double,
    nextMajorMilestoneEstimatedAt: Date?,
    oneMillionResetPromiseStillApplies: Bool
  ) {
    self.latestUsersMillion = latestUsersMillion
    self.latestObservedAt = latestObservedAt
    self.growthMillionPerDay = growthMillionPerDay
    self.nextMillionUsers = nextMillionUsers
    self.nextMillionEstimatedAt = nextMillionEstimatedAt
    self.nextMajorMilestoneUsers = nextMajorMilestoneUsers
    self.nextMajorMilestoneEstimatedAt = nextMajorMilestoneEstimatedAt
    self.oneMillionResetPromiseStillApplies = oneMillionResetPromiseStillApplies
  }
}

public struct ResetForecastSnapshot: Codable, Equatable, Sendable {
  public static let maximumProbabilityAge: TimeInterval = 6 * 3_600

  public let probability24Hours: Double?
  public let probability48Hours: Double?
  public let confidence: ResetForecastConfidence
  public let confidenceNote: String?
  public let sourceUpdatedAt: Date
  public let fetchedAt: Date
  public let lastResetAt: Date?
  public let modelVersion: String?
  public let recentMedianDays: Double?
  public let weightedMeanDays: Double?
  public let commonWindowLabel: String?
  public let commonWindowTimeZone: String?
  public let latestSignalSummary: String?
  public let latestSignalURL: URL?
  public let milestones: [ResetMilestoneObservation]
  public let sourceURL: URL

  public init(
    probability24Hours: Double?,
    probability48Hours: Double?,
    confidence: ResetForecastConfidence,
    confidenceNote: String?,
    sourceUpdatedAt: Date,
    fetchedAt: Date,
    lastResetAt: Date?,
    modelVersion: String?,
    recentMedianDays: Double?,
    weightedMeanDays: Double?,
    commonWindowLabel: String?,
    commonWindowTimeZone: String?,
    latestSignalSummary: String?,
    latestSignalURL: URL?,
    milestones: [ResetMilestoneObservation],
    sourceURL: URL = URL(string: "https://codex-reset.com/tibo")!
  ) {
    self.probability24Hours = Self.validProbability(probability24Hours)
    self.probability48Hours = Self.validProbability(probability48Hours)
    self.confidence = confidence
    self.confidenceNote = confidenceNote
    self.sourceUpdatedAt = sourceUpdatedAt
    self.fetchedAt = fetchedAt
    self.lastResetAt = lastResetAt
    self.modelVersion = modelVersion
    self.recentMedianDays = recentMedianDays
    self.weightedMeanDays = weightedMeanDays
    self.commonWindowLabel = commonWindowLabel
    self.commonWindowTimeZone = commonWindowTimeZone
    self.latestSignalSummary = latestSignalSummary
    self.latestSignalURL = latestSignalURL
    self.milestones = milestones.sorted { $0.announcedAt < $1.announcedAt }
    self.sourceURL = sourceURL
  }

  public func availableProbability48Hours(at now: Date = Date()) -> Double? {
    guard now.timeIntervalSince(sourceUpdatedAt) >= -300,
      now.timeIntervalSince(sourceUpdatedAt) <= Self.maximumProbabilityAge
    else { return nil }
    return probability48Hours
  }

  public func isStale(at now: Date = Date()) -> Bool {
    availableProbability48Hours(at: now) == nil
  }

  public var milestoneProjection: ResetMilestoneProjection? {
    let ordered = milestones
      .filter { $0.usersMillion > 0 }
      .sorted { $0.announcedAt < $1.announcedAt }
    guard let latest = ordered.last else { return nil }

    let previous = ordered.dropLast().last { observation in
      observation.usersMillion < latest.usersMillion
        && observation.announcedAt < latest.announcedAt
    }
    let growth: Double?
    if let previous {
      let days = latest.announcedAt.timeIntervalSince(previous.announcedAt) / 86_400
      let delta = latest.usersMillion - previous.usersMillion
      growth = days > 0.25 && delta > 0 ? delta / days : nil
    } else {
      growth = nil
    }

    let nextMillion = floor(latest.usersMillion + 0.000_001) + 1
    let nextMajor: Double
    if latest.usersMillion < 10 {
      nextMajor = nextMillion
    } else {
      nextMajor = (floor(latest.usersMillion / 5) + 1) * 5
    }

    func estimate(_ target: Double) -> Date? {
      guard let growth, growth > 0, target > latest.usersMillion else { return nil }
      return latest.announcedAt.addingTimeInterval(
        ((target - latest.usersMillion) / growth) * 86_400)
    }

    return ResetMilestoneProjection(
      latestUsersMillion: latest.usersMillion,
      latestObservedAt: latest.announcedAt,
      growthMillionPerDay: growth,
      nextMillionUsers: nextMillion,
      nextMillionEstimatedAt: estimate(nextMillion),
      nextMajorMilestoneUsers: nextMajor,
      nextMajorMilestoneEstimatedAt: estimate(nextMajor),
      oneMillionResetPromiseStillApplies: latest.usersMillion < 10
    )
  }

  private static func validProbability(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (0...1).contains(value) else { return nil }
    return value
  }
}

public protocol ResetForecastSource: Sendable {
  func fetch() async throws -> ResetForecastSnapshot
}

public enum ResetForecastError: Error, LocalizedError, Sendable {
  case invalidResponse(String)
  case httpStatus(String, Int)
  case invalidPayload(String)

  public var errorDescription: String? {
    switch self {
    case .invalidResponse(let source): "\(source) 返回了无效响应"
    case .httpStatus(let source, let status): "\(source) HTTP \(status)"
    case .invalidPayload(let source): "\(source) 数据结构无法识别"
    }
  }
}

public struct PublicResetForecastSource: ResetForecastSource {
  private let session: URLSession
  private let forecastURL: URL
  private let timelineURL: URL

  public init(
    session: URLSession? = nil,
    forecastURL: URL = URL(string: "https://codex-reset.com/api/forecast")!,
    timelineURL: URL = URL(string: "https://codex-reset.com/api/timeline")!
  ) {
    self.session = session ?? Self.makeSession()
    self.forecastURL = forecastURL
    self.timelineURL = timelineURL
  }

  public func fetch() async throws -> ResetForecastSnapshot {
    async let forecastData = loadJSON(from: forecastURL, source: "Reset Forecast")
    async let timelineData = loadJSON(from: timelineURL, source: "Reset Timeline")
    return try await Self.parse(
      forecastData: forecastData,
      timelineData: timelineData,
      fetchedAt: Date()
    )
  }

  static func parse(
    forecastData: Data,
    timelineData: Data,
    fetchedAt: Date
  ) throws -> ResetForecastSnapshot {
    let decoder = JSONDecoder()
    guard let forecast = try? decoder.decode(ForecastEnvelope.self, from: forecastData),
      let timeline = try? decoder.decode(TimelineEnvelope.self, from: timelineData),
      let updatedAt = parseDate(forecast.updatedAt)
    else { throw ResetForecastError.invalidPayload("Codex Reset public API") }

    let milestones = timeline.milestones.compactMap { item -> ResetMilestoneObservation? in
      guard item.usersMillion > 0, let date = parseDate(item.announcedAt) else { return nil }
      return ResetMilestoneObservation(
        usersMillion: item.usersMillion,
        announcedAt: date,
        group: item.group,
        sourceURL: item.url.flatMap(URL.init(string:))
      )
    }

    let confidence = ResetForecastConfidence(rawValue: forecast.confidence?.lowercased() ?? "")
      ?? .unavailable
    return ResetForecastSnapshot(
      probability24Hours: forecast.probabilities?.siteProbability24Hours,
      probability48Hours: forecast.probabilities?.siteProbability48Hours,
      confidence: confidence,
      confidenceNote: forecast.confidenceNote,
      sourceUpdatedAt: updatedAt,
      fetchedAt: fetchedAt,
      lastResetAt: forecast.lastResetAt.flatMap(parseDate),
      modelVersion: forecast.model?.version,
      recentMedianDays: forecast.cadence?.recentMedianDays,
      weightedMeanDays: forecast.cadence?.weightedMeanDays,
      commonWindowLabel: forecast.timeWindow?.label,
      commonWindowTimeZone: forecast.timeWindow?.timezone,
      latestSignalSummary: forecast.latestAlert?.summary,
      latestSignalURL: forecast.latestAlert?.url.flatMap(URL.init(string:)),
      milestones: milestones
    )
  }

  private func loadJSON(from url: URL, source: String) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.setValue("CodexFloat/0.2 (+local read-only companion)", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ResetForecastError.invalidResponse(source)
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ResetForecastError.httpStatus(source, http.statusCode)
    }
    guard !data.isEmpty else { throw ResetForecastError.invalidResponse(source) }
    return data
  }

  private static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    return URLSession(configuration: configuration)
  }

  private static func parseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
  }
}

private struct ForecastEnvelope: Decodable {
  let updatedAt: String
  let lastResetAt: String?
  let confidence: String?
  let confidenceNote: String?
  let probabilities: ForecastProbabilities?
  let model: ForecastModel?
  let cadence: ForecastCadence?
  let timeWindow: ForecastTimeWindow?
  let latestAlert: ForecastLatestAlert?

  enum CodingKeys: String, CodingKey {
    case updatedAt = "updated_at"
    case lastResetAt = "last_reset_at"
    case confidence
    case confidenceNote = "confidence_note"
    case probabilities, model, cadence
    case timeWindow = "time_window"
    case latestAlert = "latest_alert"
  }
}

private struct ForecastProbabilities: Decodable {
  let raw24Hours: Double?
  let raw48Hours: Double?
  let rounded24Hours: Double?
  let rounded48Hours: Double?

  var siteProbability24Hours: Double? {
    siteProbability(roundedPercent: rounded24Hours, rawProbability: raw24Hours)
  }

  var siteProbability48Hours: Double? {
    siteProbability(roundedPercent: rounded48Hours, rawProbability: raw48Hours)
  }

  private func siteProbability(
    roundedPercent: Double?,
    rawProbability: Double?
  ) -> Double? {
    if let roundedPercent {
      guard roundedPercent.isFinite, (0...100).contains(roundedPercent) else { return nil }
      return roundedPercent / 100
    }
    return rawProbability
  }

  enum CodingKeys: String, CodingKey {
    case raw24Hours = "raw_24h"
    case raw48Hours = "raw_48h"
    case rounded24Hours = "rounded_24h"
    case rounded48Hours = "rounded_48h"
  }
}

private struct ForecastModel: Decodable {
  let version: String?
}

private struct ForecastCadence: Decodable {
  let recentMedianDays: Double?
  let weightedMeanDays: Double?

  enum CodingKeys: String, CodingKey {
    case recentMedianDays = "recent_median_days"
    case weightedMeanDays = "weighted_mean_days"
  }
}

private struct ForecastTimeWindow: Decodable {
  let label: String?
  let timezone: String?
}

private struct ForecastLatestAlert: Decodable {
  let summary: String?
  let url: String?
}

private struct TimelineEnvelope: Decodable {
  let milestones: [TimelineMilestone]
}

private struct TimelineMilestone: Decodable {
  let usersMillion: Double
  let announcedAt: String
  let group: String?
  let url: String?

  enum CodingKeys: String, CodingKey {
    case usersMillion = "users_m"
    case announcedAt = "announced_at"
    case group, url
  }
}
