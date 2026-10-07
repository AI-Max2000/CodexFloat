import Foundation

/// Public, experimental 48h automatic-reset forecast. No account data is sent.
public struct WhenResetForecastSource: ResetForecastSource {
  public static let homepageURL = URL(string: "https://whenreset.app/")!
  public var sourceURL: URL { Self.homepageURL }
  private let session: URLSession

  public init(session: URLSession? = nil) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    self.session = session ?? URLSession(configuration: configuration)
  }

  public func fetch() async throws -> ResetForecastSnapshot {
    var request = URLRequest(url: URL(string: "https://whenreset.app/api/forecast")!)
    request.timeoutInterval = 15
    request.setValue("CodexFloat/0.2 (+local read-only companion)", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ResetForecastError.invalidResponse("WhenReset")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ResetForecastError.httpStatus("WhenReset", http.statusCode)
    }
    guard http.url?.host == sourceURL.host, http.mimeType == "application/json" else {
      throw ResetForecastError.invalidResponse("WhenReset")
    }
    return try Self.parse(data: data, fetchedAt: Date())
  }

  static func parse(data: Data, fetchedAt: Date) throws -> ResetForecastSnapshot {
    guard !data.isEmpty, data.count <= 256_000,
      let payload = try? JSONDecoder().decode(Payload.self, from: data),
      payload.product == "codex", payload.target == "global hard reset (banked excluded)",
      payload.sample_n > 0, !payload.model.isEmpty,
      let updated = parseDate(payload.updated_at), let ledger = parseDate(payload.data_as_of),
      ledger <= updated.addingTimeInterval(300),
      payload.hours_since_last.isFinite, (0...87_600).contains(payload.hours_since_last),
      (0...1).contains(payload.probabilities.raw_24h),
      (0...1).contains(payload.probabilities.raw_48h),
      payload.probabilities.raw_48h >= payload.probabilities.raw_24h
    else { throw ResetForecastError.invalidPayload("WhenReset") }
    guard (-300...ResetForecastSnapshot.maximumProbabilityAge).contains(fetchedAt.timeIntervalSince(updated))
    else { throw ResetForecastError.staleData("WhenReset") }

    // data_as_of is a ledger timestamp, not a forecast heartbeat. It need not
    // change when no event occurs. hours_since_last is the provider's baseline,
    // NOT independent proof of a completed reset (nor a future reset deadline).
    return ResetForecastSnapshot(
      probability24Hours: payload.probabilities.raw_24h,
      probability48Hours: payload.probabilities.raw_48h,
      confidence: .low, confidenceNote: "Experimental historical-interval estimate.",
      sourceUpdatedAt: updated, fetchedAt: fetchedAt,
      lastResetAt: updated.addingTimeInterval(-payload.hours_since_last * 3_600),
      modelVersion: payload.model, recentMedianDays: nil, weightedMeanDays: nil,
      commonWindowLabel: nil, commonWindowTimeZone: nil, latestSignalSummary: nil,
      latestSignalURL: nil, milestones: [], sourceURL: homepageURL
    )
  }

  private static func parseDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }

  private struct Payload: Decodable {
    let updated_at: String
    let data_as_of: String
    let product: String
    let target: String
    let model: String
    let sample_n: Int
    let hours_since_last: Double
    let probabilities: Probabilities
    struct Probabilities: Decodable {
      let raw_24h: Double
      let raw_48h: Double
    }
  }
}
