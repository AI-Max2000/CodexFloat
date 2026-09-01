import CryptoKit
import Foundation

public enum QuotaDecodeError: Error, LocalizedError, Sendable {
  case invalidJSON
  case missingResult
  case missingRateLimits

  public var errorDescription: String? {
    switch self {
    case .invalidJSON: "Codex 返回了无效 JSON"
    case .missingResult: "Codex 响应缺少 result"
    case .missingRateLimits: "Codex 响应没有额度窗口"
    }
  }
}

public enum QuotaDecoder {
  public static func decodeResponse(_ data: Data, observedAt: Date = Date()) throws -> QuotaSnapshot
  {
    guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw QuotaDecodeError.invalidJSON
    }
    guard let result = envelope["result"] as? [String: Any] else {
      throw QuotaDecodeError.missingResult
    }
    return try decodeResult(result, observedAt: observedAt)
  }

  public static func decodeResult(_ result: [String: Any], observedAt: Date = Date()) throws
    -> QuotaSnapshot
  {
    var buckets: [(String, [String: Any])] = []
    if let dynamic = result["rateLimitsByLimitId"] as? [String: Any] {
      buckets = dynamic.compactMap { key, value in
        guard let dictionary = value as? [String: Any] else { return nil }
        return (key, dictionary)
      }.sorted { $0.0 < $1.0 }
    }
    if buckets.isEmpty, let legacy = result["rateLimits"] as? [String: Any] {
      buckets = [(string(legacy["limitId"]) ?? "codex", legacy)]
    }
    guard !buckets.isEmpty else { throw QuotaDecodeError.missingRateLimits }

    var windows: [RateLimitWindow] = []
    var planType: String?
    var creditBalance: Double?
    var hasCredits: Bool?
    var spendControlReached: Bool?

    for (fallbackID, bucket) in buckets {
      let limitID = string(bucket["limitId"]) ?? fallbackID
      let limitName = string(bucket["limitName"])
      planType = planType ?? string(bucket["planType"])
      let reachedType = string(bucket["rateLimitReachedType"])
      for (key, label) in [("primary", "主窗口"), ("secondary", "次窗口")] {
        guard let raw = bucket[key] as? [String: Any], let used = double(raw["usedPercent"]) else {
          continue
        }
        windows.append(
          RateLimitWindow(
            id: "\(limitID):\(key)",
            limitID: limitID,
            limitName: limitName,
            windowName: label,
            usedPercent: used,
            windowDurationMinutes: integer(raw["windowDurationMins"]),
            resetsAt: date(raw["resetsAt"]),
            reachedType: reachedType
          ))
      }
      if let credits = bucket["credits"] as? [String: Any] {
        creditBalance = creditBalance ?? double(credits["balance"] ?? credits["remaining"])
        hasCredits = hasCredits ?? boolean(credits["hasCredits"])
        spendControlReached = spendControlReached ?? boolean(credits["spendControlReached"])
      }
    }

    let resetPayload = result["rateLimitResetCredits"] as? [String: Any]
    let resetCreditCount = integer(resetPayload?["availableCount"])
    let resetCredits: [ResetCredit] = (resetPayload?["credits"] as? [[String: Any]] ?? []).map {
      credit in
      let opaqueID = string(credit["id"]) ?? UUID().uuidString
      let digest = SHA256.hash(data: Data(opaqueID.utf8)).prefix(12).map {
        String(format: "%02x", $0)
      }.joined()
      return ResetCredit(
        id: digest,
        resetType: string(credit["resetType"]),
        status: string(credit["status"]),
        grantedAt: date(credit["grantedAt"]),
        expiresAt: date(credit["expiresAt"]),
        title: string(credit["title"]),
        detail: string(credit["description"])
      )
    }

    return QuotaSnapshot(
      planType: planType,
      windows: windows.sorted {
        if $0.limitID == $1.limitID { return $0.windowName < $1.windowName }
        return $0.limitID < $1.limitID
      },
      resetCreditCount: resetCreditCount,
      resetCredits: resetCredits,
      creditBalance: creditBalance,
      hasCredits: hasCredits,
      spendControlReached: spendControlReached,
      observedAt: observedAt
    )
  }

  private static func string(_ value: Any?) -> String? {
    if value is NSNull || value == nil { return nil }
    return value as? String
  }

  private static func double(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
  }

  private static func integer(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let value = value as? String { return Int(value) }
    return nil
  }

  private static func boolean(_ value: Any?) -> Bool? {
    (value as? NSNumber)?.boolValue ?? (value as? Bool)
  }

  private static func date(_ value: Any?) -> Date? {
    double(value).map(Date.init(timeIntervalSince1970:))
  }
}
