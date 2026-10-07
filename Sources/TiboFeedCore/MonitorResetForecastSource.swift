import Foundation

/// Selected using the common-case 48h replay documented in docs/qa-reset-forecast-source.md.
/// The public homepage is the source: never execute its scripts or send local account data.
public struct MonitorResetForecastSource: ResetForecastSource {
  public static let homepageURL = URL(string: "https://codexreset.org/")!
  static let maximumResponseBytes = 1_500_000
  public var sourceURL: URL { Self.homepageURL }
  private let session: URLSession

  public init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      configuration.urlCache = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.timeoutIntervalForRequest = 20
      configuration.timeoutIntervalForResource = 30
      self.session = URLSession(configuration: configuration)
    }
  }

  public func fetch() async throws -> ResetForecastSnapshot {
    var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData)
    request.timeoutInterval = 20
    request.setValue("CodexFloat/0.2 (+local read-only companion)", forHTTPHeaderField: "User-Agent")
    request.setValue("text/html", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ResetForecastError.invalidResponse("Codex Reset Monitor")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw ResetForecastError.httpStatus("Codex Reset Monitor", http.statusCode)
    }
    guard http.url?.host == sourceURL.host,
      http.mimeType == "text/html" || http.mimeType == "application/xhtml+xml"
    else { throw ResetForecastError.invalidResponse("Codex Reset Monitor") }
    return try Self.parse(htmlData: data, fetchedAt: Date())
  }

  static func parse(htmlData: Data, fetchedAt: Date) throws -> ResetForecastSnapshot {
    guard !htmlData.isEmpty, htmlData.count <= maximumResponseBytes,
      let html = String(data: htmlData, encoding: .utf8)
    else { throw ResetForecastError.invalidPayload("Codex Reset Monitor") }

    // The SSR page animates a visible 0% towards the final value. The accessible
    // label contains the final percentage, so an actual zero remains valid too.
    func probability(hours: Int) -> Double? {
      let pattern = #"aria-label="[^"<>]*probability of another global reset within "#
        + String(hours) + #" hours:\s*([0-9]+(?:\.[0-9]+)?)%""#
      guard let value = capture(pattern, in: html).flatMap(Double.init),
        value.isFinite, (0...100).contains(value)
      else { return nil }
      return value / 100
    }

    // This is the provider's snapshot timestamp, NOT its minute-by-minute
    // "Last check" heartbeat or our fetch time. Read the serialized header as
    // text only; reject a changed schema instead of inventing freshness.
    let headerPattern = #"snapshot:\$R\[\d+\]=\{status:"(?:ok|healthy|degraded)",updatedAt:"([^"]+)",forecastStatus:"current""#
    guard let updatedAt = capture(headerPattern, in: html).flatMap(parseDate),
      let p24 = probability(hours: 24), let p48 = probability(hours: 48), p48 >= p24
    else { throw ResetForecastError.invalidPayload("Codex Reset Monitor") }
    guard fetchedAt.timeIntervalSince(updatedAt) >= -300,
      fetchedAt.timeIntervalSince(updatedAt) <= ResetForecastSnapshot.maximumProbabilityAge
    else { throw ResetForecastError.staleData("Codex Reset Monitor") }

    let resetPattern = #"<time\b(?=[^>]*data-testid="reset-exact-time")[^>]*dateTime="([^"]+)""#
    let modelPattern = #"forecast:\$R\[\d+\]=\{[^\n]{0,200}?algorithmVersion:"([^"]+)""#
    return ResetForecastSnapshot(
      probability24Hours: p24,
      probability48Hours: p48,
      confidence: .low,
      confidenceNote: "Experimental community forecast; historical ranking is not a guarantee.",
      sourceUpdatedAt: updatedAt,
      fetchedAt: fetchedAt,
      lastResetAt: capture(resetPattern, in: html).flatMap(parseDate),
      modelVersion: capture(modelPattern, in: html),
      recentMedianDays: nil,
      weightedMeanDays: nil,
      commonWindowLabel: nil,
      commonWindowTimeZone: nil,
      latestSignalSummary: nil,
      latestSignalURL: nil,
      milestones: [],
      sourceURL: homepageURL
    )
  }

  private static func capture(_ pattern: String, in text: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range])
  }

  private static func parseDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
