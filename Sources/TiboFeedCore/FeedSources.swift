import CodexQuotaCore
import Foundation

public enum FeedError: Error, LocalizedError, Sendable {
  case invalidResponse(String)
  case httpStatus(String, Int)
  case parse(String)
  case allSourcesFailed([String])

  public var errorDescription: String? {
    switch self {
    case .invalidResponse(let source): "\(source) 返回了无效响应"
    case .httpStatus(let source, let code): "\(source) HTTP \(code)"
    case .parse(let source): "\(source) 页面结构无法识别"
    case .allSourcesFailed(let errors): "全部帖子来源不可用：\(errors.joined(separator: "；"))"
    }
  }
}

public struct TwiscanFeedSource: FeedSource {
  public let name = "Twiscan"
  private let session: URLSession
  private let url = URL(string: "https://twiscan.com/en/x/thsottiaux")!

  public init(session: URLSession? = nil) { self.session = session ?? makeEphemeralFeedSession() }

  public func fetch() async throws -> [FeedPost] {
    let html = try await loadHTML(url: url, source: name, session: session)
    return try Self.parse(html: html, now: Date())
  }

  static func parse(html: String, now: Date) throws -> [FeedPost] {
    let links = HTMLUtilities.matches(
      #"href="https://twiscan\.com/en/x/thsottiaux/([0-9]+)">([^<]*)</a>"#, in: html)
    var seen = Set<String>()
    var posts: [FeedPost] = []
    for link in links where link.count >= 3 {
      let id = link[1]
      guard seen.insert(id).inserted else { continue }
      let escapedID = NSRegularExpression.escapedPattern(for: id)
      guard
        let textMatch = HTMLUtilities.first(
          #"id="clamp-"# + escapedID + #"-0"[^>]*>(.*?)</div>"#, in: html), textMatch.count > 1
      else { continue }
      let text = HTMLUtilities.plainText(textMatch[1])
      guard !text.isEmpty, let originalURL = URL(string: "https://x.com/thsottiaux/status/\(id)")
      else { continue }
      posts.append(
        FeedPost(
          id: id,
          text: text,
          postedAt: Self.parseDateLabel(HTMLUtilities.plainText(link[2]), relativeTo: now),
          originalURL: originalURL,
          source: "Twiscan",
          fetchedAt: now
        ))
    }
    guard !posts.isEmpty else { throw FeedError.parse("Twiscan") }
    return posts
  }

  private static func parseDateLabel(_ label: String, relativeTo now: Date) -> Date? {
    let absolute = DateFormatter()
    absolute.locale = Locale(identifier: "en_US_POSIX")
    // Twiscan renders absolute post timestamps in UTC. Treating these labels as the
    // Mac's local time shifts the underlying instant before the UI has a chance to
    // format it for the selected language.
    absolute.timeZone = TimeZone(secondsFromGMT: 0)
    absolute.dateFormat = "yyyy.MM.dd HH:mm"
    if let date = absolute.date(from: label) { return date }

    let lower = label.lowercased().replacingOccurrences(of: " ", with: "")
    let units: [(String, TimeInterval)] = [
      ("minute", 60), ("hour", 3_600), ("day", 86_400),
    ]
    for (unit, seconds) in units where lower.contains(unit) {
      if let match = HTMLUtilities.first(#"([0-9]+)"#, in: lower), let amount = Double(match[1]) {
        return now.addingTimeInterval(-amount * seconds)
      }
    }
    if lower.contains("justnow") { return now }
    return nil
  }
}

public struct TwiteeFeedSource: FeedSource {
  public let name = "Twitee"
  private let session: URLSession
  private let url = URL(string: "https://twitee.co/thsottiaux")!

  public init(session: URLSession? = nil) { self.session = session ?? makeEphemeralFeedSession() }

  public func fetch() async throws -> [FeedPost] {
    let encodedHTML = try await loadHTML(url: url, source: name, session: session)
    return try Self.parse(html: encodedHTML, now: Date())
  }

  static func parse(html encodedHTML: String, now: Date) throws -> [FeedPost] {
    let html = HTMLUtilities.decodeEntities(encodedHTML)
    let pattern =
      #""id":\[0,"([0-9]+)"\].{0,1800}?"handle":\[0,"thsottiaux"\].{0,1800}?"text":\[0,"((?:\\.|[^"\\])*)"\].{0,800}?"postedAt":\[0,"([^"]+)"\]"#
    let matches = HTMLUtilities.matches(pattern, in: html)
    let iso = ISO8601DateFormatter()
    var seen = Set<String>()
    let posts: [FeedPost] = matches.compactMap { match in
      guard match.count >= 4, seen.insert(match[1]).inserted else { return nil }
      let id = match[1]
      let quoted = "\"\(match[2])\""
      let text = (try? JSONDecoder().decode(String.self, from: Data(quoted.utf8))) ?? match[2]
      guard let originalURL = URL(string: "https://x.com/thsottiaux/status/\(id)") else {
        return nil
      }
      return FeedPost(
        id: id,
        text: text,
        postedAt: iso.date(from: match[3]),
        originalURL: originalURL,
        source: "Twitee",
        fetchedAt: now
      )
    }
    guard !posts.isEmpty else { throw FeedError.parse("Twitee") }
    return posts
  }
}

public struct FallbackFeedSource: FeedSource {
  public let name = "Twiscan → Twitee"
  private let sources: [any FeedSource]

  public init(sources: [any FeedSource] = [TwiscanFeedSource(), TwiteeFeedSource()]) {
    self.sources = sources
  }

  public func fetch() async throws -> [FeedPost] {
    var errors: [String] = []
    for source in sources {
      do { return try await source.fetch() } catch {
        errors.append("\(source.name)：\(error.localizedDescription)")
      }
    }
    throw FeedError.allSourcesFailed(errors)
  }
}

private func loadHTML(url: URL, source: String, session: URLSession) async throws -> String {
  var request = URLRequest(url: url)
  request.timeoutInterval = 15
  request.setValue(
    "CodexFloat/0.1 (+local read-only quota companion)", forHTTPHeaderField: "User-Agent")
  request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
  let (data, response) = try await session.data(for: request)
  guard let http = response as? HTTPURLResponse else { throw FeedError.invalidResponse(source) }
  guard (200..<300).contains(http.statusCode) else {
    throw FeedError.httpStatus(source, http.statusCode)
  }
  guard let html = String(data: data, encoding: .utf8) else {
    throw FeedError.invalidResponse(source)
  }
  return html
}

private func makeEphemeralFeedSession() -> URLSession {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.httpCookieStorage = nil
  configuration.httpShouldSetCookies = false
  configuration.urlCache = nil
  configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
  configuration.timeoutIntervalForRequest = 15
  configuration.timeoutIntervalForResource = 20
  return URLSession(configuration: configuration)
}
