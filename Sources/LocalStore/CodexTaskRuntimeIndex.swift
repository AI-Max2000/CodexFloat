import CodexQuotaCore
import Foundation
import SQLite3

public enum CodexTurnRuntimeStatus: String, Sendable {
  case inProgress
  case completed
  case failed
  case interrupted
  case unknown
}

public struct CodexTaskRuntimeState: Equatable, Sendable {
  public let threadID: String
  public let turnID: String
  public let status: CodexTurnRuntimeStatus
  public let startedAt: Date?
  public let completedAt: Date?

  public init(
    threadID: String,
    turnID: String,
    status: CodexTurnRuntimeStatus,
    startedAt: Date?,
    completedAt: Date?
  ) {
    self.threadID = threadID
    self.turnID = turnID
    self.status = status
    self.startedAt = startedAt
    self.completedAt = completedAt
  }

  public func taskStatus(
    now: Date = Date(),
    staleInProgressAfter: TimeInterval = 24 * 60 * 60
  ) -> CodexTaskStatus {
    switch status {
    case .inProgress:
      guard let startedAt, now.timeIntervalSince(startedAt) <= staleInProgressAfter else {
        return .idle
      }
      return .working
    case .failed:
      return .error
    case .completed, .interrupted, .unknown:
      return .idle
    }
  }
}

public enum CodexTaskRuntimeIndexError: Error, LocalizedError, Sendable {
  case databaseNotFound
  case open(String)
  case query(String)

  public var errorDescription: String? {
    switch self {
    case .databaseNotFound:
      return "未找到 Codex 任务状态索引"
    case .open(let message):
      return "无法只读打开 Codex 任务状态索引：\(message)"
    case .query(let message):
      return "无法读取 Codex 任务状态：\(message)"
    }
  }
}

public actor CodexTaskRuntimeIndex {
  private let explicitDatabaseURL: URL?
  private let codexHomeURL: URL

  public init(
    databaseURL: URL? = nil,
    codexHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      ".codex", isDirectory: true)
  ) {
    explicitDatabaseURL = databaseURL
    self.codexHomeURL = codexHomeURL
  }

  public func latestStates(for threadIDs: [String]) throws -> [String: CodexTaskRuntimeState] {
    let uniqueIDs = Array(Set(threadIDs.filter { !$0.isEmpty }))
    guard !uniqueIDs.isEmpty else { return [:] }
    let databaseURL = try resolvedDatabaseURL()

    var database: OpaquePointer?
    guard
      sqlite3_open_v2(
        databaseURL.path,
        &database,
        SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
        nil
      ) == SQLITE_OK
    else {
      let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "未知 SQLite 错误"
      if let database { sqlite3_close(database) }
      throw CodexTaskRuntimeIndexError.open(message)
    }
    defer { sqlite3_close(database) }

    let placeholders = Array(repeating: "?", count: uniqueIDs.count).joined(separator: ",")
    let sql = """
      WITH latest_turns AS (
          SELECT thread_id, turn_id, status, started_at, completed_at,
                 ROW_NUMBER() OVER (
                     PARTITION BY thread_id
                     ORDER BY rollout_ordinal DESC
                 ) AS row_number
          FROM thread_turns
          WHERE thread_id IN (\(placeholders))
      )
      SELECT thread_id, turn_id, status, started_at, completed_at
      FROM latest_turns
      WHERE row_number = 1;
      """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw CodexTaskRuntimeIndexError.query(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }

    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, threadID) in uniqueIDs.enumerated() {
      guard
        sqlite3_bind_text(statement, Int32(offset + 1), threadID, -1, transient) == SQLITE_OK
      else {
        throw CodexTaskRuntimeIndexError.query("任务 ID 参数绑定失败")
      }
    }

    var result: [String: CodexTaskRuntimeState] = [:]
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { break }
      guard step == SQLITE_ROW else {
        throw CodexTaskRuntimeIndexError.query(String(cString: sqlite3_errmsg(database)))
      }
      guard
        let threadText = sqlite3_column_text(statement, 0),
        let turnText = sqlite3_column_text(statement, 1),
        let statusText = sqlite3_column_text(statement, 2)
      else { continue }
      let threadID = String(cString: threadText)
      result[threadID] = CodexTaskRuntimeState(
        threadID: threadID,
        turnID: String(cString: turnText),
        status: CodexTurnRuntimeStatus(rawValue: String(cString: statusText)) ?? .unknown,
        startedAt: date(column: 3, statement: statement),
        completedAt: date(column: 4, statement: statement)
      )
    }
    return result
  }

  private func resolvedDatabaseURL() throws -> URL {
    if let explicitDatabaseURL { return explicitDatabaseURL }
    let candidates = try FileManager.default.contentsOfDirectory(
      at: codexHomeURL,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ).filter { url in
      url.pathExtension == "sqlite" && url.lastPathComponent.hasPrefix("thread_history_")
    }
    guard
      let newest = candidates.max(by: { databaseVersion($0) < databaseVersion($1) })
    else { throw CodexTaskRuntimeIndexError.databaseNotFound }
    return newest
  }

  private func databaseVersion(_ url: URL) -> Int {
    Int(url.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? "0") ?? 0
  }

  private func date(column: Int32, statement: OpaquePointer?) -> Date? {
    guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
    let value = sqlite3_column_int64(statement, column)
    guard value > 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(value))
  }
}
