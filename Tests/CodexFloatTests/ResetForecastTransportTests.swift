import Foundation
import Testing
@testable import TiboFeedCore

/// In-memory transport: no localhost server, account state, or real requests.
private final class ForecastTransport: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let mode = request.value(forHTTPHeaderField: "X-Forecast-Fixture") ?? "timeline-down"
    let isTimeline = request.url!.path.hasSuffix("timeline")
    let status = isTimeline ? 503 : (mode == "rate-limit" ? 429 : 200)
    let type = mode == "wrong-type" ? "text/html" : "application/json"
    let finalURL = mode == "wrong-host" ? URL(string: "https://login.example/")! : request.url!
    let response = HTTPURLResponse(url: finalURL, statusCode: status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": type])!
    let payload = #"{"updated_at":"2026-10-07T10:00:00Z","last_reset_at":"2026-10-07T03:35:09Z","probabilities":{"rounded_24h":15,"rounded_48h":28}}"#
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(payload.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@Suite("Forecast transport safety")
struct ResetForecastTransportTests {
  private func session(mode: String) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ForecastTransport.self]
    configuration.httpAdditionalHeaders = ["X-Forecast-Fixture": mode]
    return URLSession(configuration: configuration)
  }

  @Test func auxiliaryTimelineOutageDoesNotDisableValidProbability() async throws {
    let session = session(mode: "timeline-down")
    defer { session.invalidateAndCancel() }
    let result = try await PublicResetForecastSource(session: session).fetch()
    #expect(result.probability48Hours == 0.28)
    #expect(result.milestones.isEmpty)
    #expect(result.sourceURL.host == "codex-reset.com")
  }

  @Test(arguments: ["rate-limit", "wrong-type", "wrong-host"])
  func rejectsBadPublicHTTPResponses(mode: String) async {
    let session = session(mode: mode)
    defer { session.invalidateAndCancel() }
    await #expect(throws: ResetForecastError.self) {
      try await PublicResetForecastSource(session: session).fetch()
    }
    await #expect(throws: ResetForecastError.self) {
      try await WhenResetForecastSource(session: session).fetch()
    }
    await #expect(throws: ResetForecastError.self) {
      try await MonitorResetForecastSource(session: session).fetch()
    }
  }
}
