import Foundation

public enum CodexTaskStatus: String, Codable, Equatable, Sendable {
  case idle
  case working
  case error

  public var label: String {
    switch self {
    case .idle: "已完成 · 空闲"
    case .working: "工作中"
    case .error: "报错"
    }
  }
}

public struct CodexTask: Codable, Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let status: CodexTaskStatus
  public let updatedAt: Date
  public let source: String?

  public init(
    id: String,
    title: String,
    status: CodexTaskStatus,
    updatedAt: Date,
    source: String?
  ) {
    self.id = id
    self.title = title
    self.status = status
    self.updatedAt = updatedAt
    self.source = source
  }

  public func withStatus(_ status: CodexTaskStatus, updatedAt: Date? = nil) -> CodexTask {
    CodexTask(
      id: id,
      title: title,
      status: status,
      updatedAt: updatedAt ?? self.updatedAt,
      source: source
    )
  }

  public var deepLink: URL? {
    var components = URLComponents()
    components.scheme = "codex"
    components.host = "threads"
    components.path = "/\(id)"
    return components.url
  }
}

public enum CodexTaskDecoder {
  private struct ListResponse: Decodable {
    let result: ResultBody
  }

  private struct ResultBody: Decodable {
    let data: [ThreadSummary]
  }

  private struct ThreadSummary: Decodable {
    let id: String
    let name: String?
    let updatedAt: Double
    let recencyAt: Double?
    let source: String?
    let status: RuntimeStatus?
  }

  private struct RuntimeStatus: Decodable {
    let type: String
  }

  public static func decodeListResponse(_ data: Data) throws -> [CodexTask] {
    let response = try JSONDecoder().decode(ListResponse.self, from: data)
    return response.result.data.map { thread in
      CodexTask(
        id: thread.id,
        title: normalizedTitle(thread.name),
        status: normalizedStatus(thread.status?.type),
        updatedAt: Date(timeIntervalSince1970: thread.recencyAt ?? thread.updatedAt),
        source: thread.source
      )
    }
  }

  private static func normalizedTitle(_ name: String?) -> String {
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? "未命名任务" : trimmed
  }

  private static func normalizedStatus(_ type: String?) -> CodexTaskStatus {
    switch type {
    case "active": .working
    case "systemError": .error
    default: .idle
    }
  }
}
