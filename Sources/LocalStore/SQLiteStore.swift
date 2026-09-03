import CodexQuotaCore
import Foundation
import SQLite3
import TiboFeedCore

public enum StoreError: Error, LocalizedError {
  case open(String)
  case execute(String)
  case encode(String)
  case decode(String)

  public var errorDescription: String? {
    switch self {
    case .open(let message), .execute(let message), .encode(let message), .decode(let message):
      message
    }
  }
}

public actor SQLiteStore {
  public static let notificationRetention: TimeInterval = 90 * 24 * 3_600
  public static let maximumNotificationKeyCount = 1_000

  private final class Connection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
  }

  private let connection: Connection
  private var database: OpaquePointer? { connection.pointer }
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()
  public let databaseURL: URL

  public init(databaseURL: URL? = nil) throws {
    let url: URL
    if let databaseURL {
      url = databaseURL
    } else {
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask)[0]
      let directory = applicationSupport.appendingPathComponent("CodexFloat", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      url = directory.appendingPathComponent("state.sqlite")
    }
    self.databaseURL = url

    var handle: OpaquePointer?
    guard
      sqlite3_open_v2(
        url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK
    else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "未知 SQLite 错误"
      if let handle { sqlite3_close(handle) }
      throw StoreError.open("无法打开本地缓存：\(message)")
    }
    guard let handle else { throw StoreError.open("SQLite 未返回数据库句柄") }
    connection = Connection(handle)
    try Self.execute(handle, sql: "PRAGMA journal_mode=WAL;")
    try Self.execute(handle, sql: "PRAGMA synchronous=NORMAL;")
    try Self.execute(
      handle,
      sql: """
        CREATE TABLE IF NOT EXISTS quota_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            observed_at REAL NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS feed_posts (
            post_id TEXT PRIMARY KEY,
            posted_at REAL,
            payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS assessments (
            post_id TEXT PRIMARY KEY,
            payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS notification_keys (
            notification_key TEXT PRIMARY KEY,
            created_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS codex_tasks (
            thread_id TEXT PRIMARY KEY,
            updated_at REAL NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE TABLE IF NOT EXISTS reset_forecasts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_updated_at REAL NOT NULL,
            payload BLOB NOT NULL
        );
        """)
    try Self.execute(
      handle,
      sql: """
        DELETE FROM notification_keys
        WHERE notification_key LIKE 'quota-five-hour-%'
          AND notification_key NOT LIKE 'quota-five-hour-v2-%';
        DELETE FROM notification_keys
        WHERE created_at < strftime('%s', 'now') - 7776000;
        DELETE FROM notification_keys
        WHERE notification_key NOT IN (
          SELECT notification_key FROM notification_keys
          ORDER BY created_at DESC, notification_key DESC
          LIMIT 1000
        );
        """)
  }

  public func save(snapshot: QuotaSnapshot) throws {
    let data = try encoded(snapshot)
    try executePrepared(
      "INSERT INTO quota_snapshots(observed_at, payload) VALUES(?, ?);",
      bindings: [.double(snapshot.observedAt.timeIntervalSince1970), .blob(data)]
    )
    try executePrepared(
      "DELETE FROM quota_snapshots WHERE id NOT IN (SELECT id FROM quota_snapshots ORDER BY id DESC LIMIT 288);"
    )
  }

  public func latestSnapshot() throws -> QuotaSnapshot? {
    guard let data = try firstBlob("SELECT payload FROM quota_snapshots ORDER BY id DESC LIMIT 1;")
    else { return nil }
    return try decoded(QuotaSnapshot.self, from: data)
  }

  public func save(posts: [FeedPost], assessments: [ActivityAssessment]) throws {
    for post in posts {
      let data = try encoded(post)
      try executePrepared(
        "INSERT OR REPLACE INTO feed_posts(post_id, posted_at, payload) VALUES(?, ?, ?);",
        bindings: [.text(post.id), .double(post.postedAt?.timeIntervalSince1970 ?? 0), .blob(data)]
      )
    }
    for assessment in assessments {
      let data = try encoded(assessment)
      try executePrepared(
        "INSERT OR REPLACE INTO assessments(post_id, payload) VALUES(?, ?);",
        bindings: [.text(assessment.postID), .blob(data)]
      )
    }
    try executePrepared(
      "DELETE FROM feed_posts WHERE post_id NOT IN (SELECT post_id FROM feed_posts ORDER BY posted_at DESC LIMIT 100);"
    )
    try executePrepared(
      "DELETE FROM assessments WHERE post_id NOT IN (SELECT post_id FROM feed_posts);"
    )
  }

  public func latestPosts(limit: Int = 100) throws -> [FeedPost] {
    try blobRows("SELECT payload FROM feed_posts ORDER BY posted_at DESC LIMIT ?;", integer: limit)
      .map { try decoded(FeedPost.self, from: $0) }
  }

  public func assessmentsByPostID() throws -> [String: ActivityAssessment] {
    var result: [String: ActivityAssessment] = [:]
    for data in try blobRows("SELECT payload FROM assessments;") {
      let assessment = try decoded(ActivityAssessment.self, from: data)
      result[assessment.postID] = assessment
    }
    return result
  }

  public func save(resetForecast: ResetForecastSnapshot) throws {
    let data = try encoded(resetForecast)
    try executePrepared(
      "INSERT INTO reset_forecasts(source_updated_at, payload) VALUES(?, ?);",
      bindings: [.double(resetForecast.sourceUpdatedAt.timeIntervalSince1970), .blob(data)]
    )
    try executePrepared(
      "DELETE FROM reset_forecasts WHERE id NOT IN (SELECT id FROM reset_forecasts ORDER BY id DESC LIMIT 24);"
    )
  }

  public func latestResetForecast() throws -> ResetForecastSnapshot? {
    guard
      let data = try firstBlob(
        "SELECT payload FROM reset_forecasts ORDER BY source_updated_at DESC, id DESC LIMIT 1;"
      )
    else { return nil }
    return try decoded(ResetForecastSnapshot.self, from: data)
  }

  public func save(tasks: [CodexTask]) throws {
    for task in tasks {
      let data = try encoded(task)
      try executePrepared(
        "INSERT OR REPLACE INTO codex_tasks(thread_id, updated_at, payload) VALUES(?, ?, ?);",
        bindings: [.text(task.id), .double(task.updatedAt.timeIntervalSince1970), .blob(data)]
      )
    }
    try executePrepared(
      "DELETE FROM codex_tasks WHERE thread_id NOT IN (SELECT thread_id FROM codex_tasks ORDER BY updated_at DESC LIMIT 50);"
    )
  }

  public func recentTasks(limit: Int = 8) throws -> [CodexTask] {
    try blobRows(
      "SELECT payload FROM codex_tasks ORDER BY updated_at DESC LIMIT ?;",
      integer: min(50, max(1, limit))
    ).map { try decoded(CodexTask.self, from: $0) }
  }

  public func claimNotification(key: String, now: Date = Date()) throws -> Bool {
    guard let database else { throw StoreError.execute("数据库未打开") }
    let before = sqlite3_total_changes(database)
    try executePrepared(
      "INSERT OR IGNORE INTO notification_keys(notification_key, created_at) VALUES(?, ?);",
      bindings: [.text(key), .double(now.timeIntervalSince1970)]
    )
    let inserted = sqlite3_total_changes(database) > before
    if inserted { try pruneNotificationKeys(now: now) }
    return inserted
  }

  public func pruneNotificationKeys(
    now: Date = Date(),
    retention: TimeInterval = SQLiteStore.notificationRetention,
    maximumCount: Int = SQLiteStore.maximumNotificationKeyCount
  ) throws {
    let safeRetention = max(0, retention)
    let safeMaximumCount = max(1, maximumCount)
    try executePrepared(
      "DELETE FROM notification_keys WHERE created_at < ?;",
      bindings: [.double(now.addingTimeInterval(-safeRetention).timeIntervalSince1970)]
    )
    let boundedDelete =
      "DELETE FROM notification_keys "
      + "WHERE notification_key NOT IN ("
      + "SELECT notification_key FROM notification_keys "
      + "ORDER BY created_at DESC, notification_key DESC LIMIT "
      + String(safeMaximumCount)
      + ");"
    try executePrepared(boundedDelete)
  }

  public func releaseNotification(key: String) throws {
    try executePrepared(
      "DELETE FROM notification_keys WHERE notification_key = ?;", bindings: [.text(key)])
  }

  public func notificationKeyCount() throws -> Int {
    guard let database else { throw StoreError.execute("数据库未打开") }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM notification_keys;", -1, &statement, nil)
        == SQLITE_OK
    else { throw StoreError.execute(String(cString: sqlite3_errmsg(database))) }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
  }

  public func databaseSize() -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber)?
      .int64Value ?? 0
  }

  private enum Binding {
    case text(String)
    case double(Double)
    case blob(Data)
  }

  private func encoded<T: Encodable>(_ value: T) throws -> Data {
    do { return try encoder.encode(value) } catch {
      throw StoreError.encode("缓存编码失败：\(error.localizedDescription)")
    }
  }

  private func decoded<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do { return try decoder.decode(type, from: data) } catch {
      throw StoreError.decode("缓存解码失败：\(error.localizedDescription)")
    }
  }

  private static func execute(_ database: OpaquePointer?, sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw StoreError.execute(String(cString: sqlite3_errmsg(database)))
    }
  }

  private func executePrepared(_ sql: String, bindings: [Binding] = []) throws {
    guard let database else { throw StoreError.execute("数据库未打开") }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.execute(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StoreError.execute(String(cString: sqlite3_errmsg(database)))
    }
  }

  private func firstBlob(_ sql: String) throws -> Data? {
    guard let database else { throw StoreError.execute("数据库未打开") }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.execute(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return data(at: 0, in: statement)
  }

  private func blobRows(_ sql: String, integer: Int? = nil) throws -> [Data] {
    guard let database else { throw StoreError.execute("数据库未打开") }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StoreError.execute(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    if let integer { sqlite3_bind_int64(statement, 1, Int64(integer)) }
    var rows: [Data] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let value = data(at: 0, in: statement) { rows.append(value) }
    }
    return rows
  }

  private func bind(_ bindings: [Binding], to statement: OpaquePointer?) throws {
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, binding) in bindings.enumerated() {
      let index = Int32(offset + 1)
      let code: Int32
      switch binding {
      case .text(let value):
        code = sqlite3_bind_text(statement, index, value, -1, transient)
      case .double(let value):
        code = sqlite3_bind_double(statement, index, value)
      case .blob(let value):
        code = value.withUnsafeBytes { bytes in
          sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(value.count), transient)
        }
      }
      guard code == SQLITE_OK else { throw StoreError.execute("SQLite 参数绑定失败") }
    }
  }

  private func data(at column: Int32, in statement: OpaquePointer?) -> Data? {
    let count = Int(sqlite3_column_bytes(statement, column))
    guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
    return Data(bytes: bytes, count: count)
  }
}
