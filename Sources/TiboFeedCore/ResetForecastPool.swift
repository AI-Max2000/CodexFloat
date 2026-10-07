import Foundation

public enum ForecastSourceIssue: String, Codable, Equatable, Sendable {
  case network, stale, invalid, missedReset
}

public struct ForecastSourceHealth: Codable, Equatable, Sendable {
  public internal(set) var snapshot: ResetForecastSnapshot?
  public internal(set) var lastAttemptAt: Date?
  public internal(set) var nextAttemptAt: Date?
  public internal(set) var lastSuccessAt: Date?
  public internal(set) var consecutiveFailures = 0
  public internal(set) var recoverySuccesses = 0
  public internal(set) var quarantined = false
  public internal(set) var cacheRevoked = false
  public internal(set) var issue: ForecastSourceIssue?
  public init() {}
}

/// Bounded persisted state: one health record/latest snapshot per configured
/// provider, plus the last displayed snapshot. Never stores raw HTML or tokens.
public struct ResetForecastPoolState: Codable, Equatable, Sendable {
  public var schemaVersion = 1
  public var sources: [String: ForecastSourceHealth] = [:]
  public var selectedID: String?
  public var selectedSnapshot: ResetForecastSnapshot?
  public var corroboratedResetAt: Date?
  public init() {}
}

public enum ForecastSourceStatus: String, Equatable, Sendable {
  case pending, healthy, unavailable, quarantined, recovering
}

public struct ResetForecastPoolReport: Equatable, Sendable {
  public struct Source: Equatable, Sendable {
    public let name: String
    public let status: ForecastSourceStatus
    public let issue: ForecastSourceIssue?
  }
  public enum Selection: String, Equatable, Sendable {
    case preferred, failover, cached, unavailable
  }
  public let selection: Selection
  public let selectedName: String?
  public let sources: [Source]
}

public struct ResetForecastProvider: Sendable {
  public let id: String
  public let name: String
  public let source: any ResetForecastSource
  /// Only independently maintained, completed-event baselines may vote on
  /// missed-event detection. A mirror/experimental ledger is a non-voter.
  public let eventEvidenceGroup: String?

  public init(id: String, name: String, source: any ResetForecastSource,
              eventEvidenceGroup: String? = nil) {
    self.id = id
    self.name = name
    self.source = source
    self.eventEvidenceGroup = eventEvidenceGroup
  }
}

public enum ResetForecastPoolError: Error, LocalizedError, Sendable {
  case unavailable
  public var errorDescription: String? { "所有重置预测来源暂不可用，等待有效数据" }
}

/// Selects ONE source, never averages incompatible or uncalibrated percentages.
/// Priority is a bootstrap/failover order, not a claim of universal accuracy.
public actor ResetForecastPool: ResetForecastSource {
  public static let pollInterval: TimeInterval = 5 * 60
  public static let probeInterval: TimeInterval = 30 * 60
  public static let failureThreshold = 3
  public static let recoveryThreshold = 2
  public static let eventTolerance: TimeInterval = 6 * 3_600

  // Used only to migrate the previously selected Monitor cache. Snapshots
  // always retain the actual provider URL, including after failover.
  public nonisolated var sourceURL: URL { MonitorResetForecastSource.homepageURL }
  private let providers: [ResetForecastProvider]
  private let clock: @Sendable () -> Date
  private var state = ResetForecastPoolState()
  private var selection: ResetForecastPoolReport.Selection = .unavailable
  private var inFlight: Task<ResetForecastSnapshot, Error>?

  public init(providers: [ResetForecastProvider] = ResetForecastPool.defaultProviders,
              clock: @escaping @Sendable () -> Date = { Date() }) {
    precondition(Set(providers.map(\.id)).count == providers.count, "Duplicate forecast provider ID")
    self.providers = providers
    self.clock = clock
  }

  public static var defaultProviders: [ResetForecastProvider] {
    [
      .init(id: "monitor", name: "Codex Reset Monitor", source: MonitorResetForecastSource(),
            eventEvidenceGroup: "monitor"),
      .init(id: "whenreset", name: "WhenReset", source: WhenResetForecastSource()),
      .init(id: "codex-reset", name: "Codex Reset", source: PublicResetForecastSource(),
            eventEvidenceGroup: "codex-reset")
    ]
  }

  public func restore(_ saved: ResetForecastPoolState?, legacySnapshot: ResetForecastSnapshot? = nil) {
    guard inFlight == nil else { return }
    state = ResetForecastPoolState()
    let now = clock()
    if let saved, saved.schemaVersion == 1 {
      for provider in providers {
        guard var health = saved.sources[provider.id],
          health.snapshot == nil || health.snapshot?.sourceURL == provider.source.sourceURL
        else { continue }
        health.consecutiveFailures = max(0, min(health.consecutiveFailures, Self.failureThreshold))
        health.recoverySuccesses = max(0, min(health.recoverySuccesses, Self.recoveryThreshold - 1))
        // A clock change/corrupt cache must not suppress polling indefinitely.
        let maximumWait = health.quarantined ? Self.probeInterval : Self.pollInterval
        if let next = health.nextAttemptAt, next > now.addingTimeInterval(maximumWait) {
          health.nextAttemptAt = now
        }
        state.sources[provider.id] = health
      }
      if let baseline = saved.corroboratedResetAt, baseline <= now.addingTimeInterval(300) {
        state.corroboratedResetAt = baseline
      }
      if let provider = providers.first(where: { $0.id == saved.selectedID }),
        let snapshot = saved.selectedSnapshot, snapshot.sourceURL == provider.source.sourceURL,
        state.sources[provider.id] != nil
      {
        state.selectedID = provider.id
        state.selectedSnapshot = snapshot
      }
    } else if let snapshot = legacySnapshot,
      snapshot.sourceURL == MonitorResetForecastSource.homepageURL,
      let provider = providers.first(where: { $0.source.sourceURL == snapshot.sourceURL }),
      Self.validationIssue(snapshot, provider: provider, now: now) == nil
    {
      var health = ForecastSourceHealth()
      health.snapshot = snapshot
      health.lastSuccessAt = snapshot.fetchedAt
      state.sources[provider.id] = health
      state.selectedID = provider.id
      state.selectedSnapshot = snapshot
    }
    selection = cachedForecast() == nil ? .unavailable : .cached
  }

  public func persistedState() -> ResetForecastPoolState { state }

  /// A known local network outage is not evidence that all providers failed.
  /// Do not increment their failure counts or impose a 30-minute recovery delay.
  public func useOfflineCache() -> ResetForecastSnapshot? {
    let cached = cachedForecast()
    selection = cached == nil ? .unavailable : .cached
    return cached
  }

  public func cachedForecast() -> ResetForecastSnapshot? {
    guard let provider = providers.first(where: { $0.id == state.selectedID }),
      let health = state.sources[provider.id], !health.cacheRevoked,
      let snapshot = state.selectedSnapshot,
      Self.validationIssue(snapshot, provider: provider, now: clock()) == nil,
      !missedReset(snapshot)
    else { return nil }
    return snapshot
  }

  public func report() -> ResetForecastPoolReport {
    let now = clock()
    return ResetForecastPoolReport(
      selection: cachedForecast() == nil ? .unavailable : selection,
      selectedName: providers.first(where: { $0.id == state.selectedID })?.name,
      sources: providers.map { provider in
        let health = state.sources[provider.id] ?? ForecastSourceHealth()
        let status: ForecastSourceStatus
        if health.quarantined {
          status = health.recoverySuccesses > 0 ? .recovering : .quarantined
        } else if isEligible(provider, now: now) {
          status = .healthy
        } else {
          status = health.lastAttemptAt == nil ? .pending : .unavailable
        }
        return .init(name: provider.name, status: status, issue: health.issue)
      }
    )
  }

  public func fetch() async throws -> ResetForecastSnapshot {
    if let inFlight { return try await inFlight.value }
    let task = Task { try await self.refresh() }
    inFlight = task
    defer { inFlight = nil }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private struct Attempt: Sendable {
    let id: String
    let snapshot: ResetForecastSnapshot?
    let issue: ForecastSourceIssue?
  }

  private func refresh() async throws -> ResetForecastSnapshot {
    try Task.checkCancellation()
    let startedAt = clock()
    let due = providers.filter { provider in
      (state.sources[provider.id]?.nextAttemptAt ?? .distantPast) <= startedAt
    }
    let attempts = await withTaskGroup(of: Attempt.self, returning: [Attempt].self) { group in
      for provider in due {
        group.addTask {
          do {
            return Attempt(id: provider.id, snapshot: try await provider.source.fetch(), issue: nil)
          } catch {
            let issue: ForecastSourceIssue
            if let error = error as? ResetForecastError {
              switch error {
              case .staleData: issue = .stale
              case .httpStatus: issue = .network
              case .invalidPayload, .invalidResponse: issue = .invalid
              }
            } else { issue = .network }
            return Attempt(id: provider.id, snapshot: nil, issue: issue)
          }
        }
      }
      var results: [Attempt] = []
      for await result in group { results.append(result) }
      return results
    }
    try Task.checkCancellation()
    let now = clock()
    for provider in due {
      guard let attempt = attempts.first(where: { $0.id == provider.id }) else { continue }
      var health = state.sources[provider.id] ?? ForecastSourceHealth()
      health.lastAttemptAt = now
      let issue = attempt.snapshot.flatMap { Self.validationIssue($0, provider: provider, now: now) }
        ?? attempt.issue
      if let issue {
        recordFailure(&health, issue: issue, now: now)
      } else if let snapshot = attempt.snapshot {
        health.snapshot = snapshot
        health.lastSuccessAt = now
        health.consecutiveFailures = 0
        if health.quarantined {
          health.recoverySuccesses += 1
          if health.recoverySuccesses >= Self.recoveryThreshold {
            health.quarantined = false
            health.recoverySuccesses = 0
            health.cacheRevoked = false
            health.issue = nil
          }
        } else {
          health.cacheRevoked = false
          health.issue = nil
        }
        health.nextAttemptAt = now.addingTimeInterval(health.quarantined ? Self.probeInterval : Self.pollInterval)
      }
      state.sources[provider.id] = health
    }

    updateCorroboratedBaseline(now: now)
    for provider in providers {
      guard var health = state.sources[provider.id], let snapshot = health.snapshot else { continue }
      if missedReset(snapshot), health.issue != .missedReset || due.contains(where: { $0.id == provider.id }) {
        let previousIssue = health.issue
        let previousDeadline = health.nextAttemptAt
        recordFailure(&health, issue: .missedReset, now: now)
        // Do not push an existing probe deadline out on every other-source poll.
        if previousIssue == .missedReset, let previousDeadline {
          health.nextAttemptAt = previousDeadline
        }
        state.sources[provider.id] = health
      }
    }

    let eligible = providers.filter { isEligible($0, now: now) }
    let chosen = eligible.first(where: { $0.id == state.selectedID }) ?? eligible.first
    if let chosen, let snapshot = state.sources[chosen.id]?.snapshot {
      state.selectedID = chosen.id
      state.selectedSnapshot = snapshot
      selection = chosen.id == providers.first?.id ? .preferred : .failover
      return snapshot
    }
    if let cached = cachedForecast() {
      selection = .cached
      return cached
    }
    selection = .unavailable
    throw ResetForecastPoolError.unavailable
  }

  private func recordFailure(_ health: inout ForecastSourceHealth, issue: ForecastSourceIssue, now: Date) {
    health.consecutiveFailures = min(Self.failureThreshold, health.consecutiveFailures + 1)
    health.recoverySuccesses = 0
    health.issue = issue
    if issue != .network { health.cacheRevoked = true }
    if issue != .network || health.consecutiveFailures >= Self.failureThreshold { health.quarantined = true }
    health.nextAttemptAt = now.addingTimeInterval(health.quarantined ? Self.probeInterval : Self.pollInterval)
  }

  private func isEligible(_ provider: ResetForecastProvider, now: Date) -> Bool {
    guard let health = state.sources[provider.id], !health.quarantined,
      health.consecutiveFailures == 0, !health.cacheRevoked,
      let snapshot = health.snapshot,
      Self.validationIssue(snapshot, provider: provider, now: now) == nil,
      !missedReset(snapshot)
    else { return false }
    return true
  }

  private static func validationIssue(_ snapshot: ResetForecastSnapshot,
                                      provider: ResetForecastProvider, now: Date) -> ForecastSourceIssue? {
    guard snapshot.sourceURL == provider.source.sourceURL,
      let p24 = snapshot.probability24Hours, let p48 = snapshot.probability48Hours,
      p24.isFinite, p48.isFinite, (0...1).contains(p24), (p24...1).contains(p48),
      let reset = snapshot.lastResetAt, reset.timeIntervalSince1970.isFinite,
      reset <= snapshot.sourceUpdatedAt.addingTimeInterval(300)
    else { return .invalid }
    guard snapshot.availableProbability48Hours(at: now) != nil else { return .stale }
    return nil
  }

  private func missedReset(_ snapshot: ResetForecastSnapshot) -> Bool {
    guard let baseline = state.corroboratedResetAt, let reset = snapshot.lastResetAt else { return false }
    return baseline.timeIntervalSince(reset) > Self.eventTolerance
  }

  private func updateCorroboratedBaseline(now: Date) {
    let evidence = providers.compactMap { provider -> (String, Date)? in
      guard let group = provider.eventEvidenceGroup,
        let health = state.sources[provider.id], health.consecutiveFailures == 0,
        let snapshot = health.snapshot,
        Self.validationIssue(snapshot, provider: provider, now: now) == nil,
        let reset = snapshot.lastResetAt else { return nil }
      return (group, reset)
    }
    // Agreement is a stale-source guard, not proof that this user's quota reset.
    // Use the earlier timestamp and generous tolerance for announcement/delivery
    // differences; a lone source, mirror, or banked-credit ledger cannot evict peers.
    for (index, first) in evidence.enumerated() {
      for second in evidence.dropFirst(index + 1) where first.0 != second.0 {
        if abs(first.1.timeIntervalSince(second.1)) <= Self.eventTolerance {
          let agreed = min(first.1, second.1)
          state.corroboratedResetAt = max(state.corroboratedResetAt ?? .distantPast, agreed)
        }
      }
    }
  }
}
