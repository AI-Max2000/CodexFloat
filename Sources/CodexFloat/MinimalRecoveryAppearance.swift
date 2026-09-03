import SwiftUI

/// Emphasis belongs to the affected quota track, never the surrounding canvas.
enum MinimalRecoveryEmphasis: Equatable {
  case resetAvailable
  case needsVerification
  case spendingLimit

  var color: Color {
    switch self {
    case .resetAvailable, .spendingLimit: .red
    case .needsVerification: .orange
    }
  }

  static func resolve(entry: QuotaDisplayEntry?, recovery: QuotaRecoveryState?) -> Self? {
    guard let window = entry?.window, let recovery,
      recovery.windows.contains(where: { $0.id == window.id }),
      QuotaRecoveryState.isWeeklyCodexWindow(window), window.remainingPercent <= 0
    else { return nil }
    switch recovery.kind {
    case .exhausted: return recovery.canOpenManualReset ? .resetAvailable : nil
    case .needsRefresh, .awaitingReset: return .needsVerification
    case .spendLimit: return .spendingLimit
    }
  }
}
