import Foundation

enum MinimalMeterStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case vertical, horizontal, ring
  var id: String { rawValue }

  var titleKey: LocalizedTextKey {
    switch self {
    case .vertical: .minimalVertical
    case .horizontal: .minimalHorizontal
    case .ring: .minimalRing
    }
  }
}

struct MinimalMeterDimensions: Codable, Equatable, Sendable {
  var length: Double
  var thickness: Double
  var scale: Double = 1

  static func defaults(for style: MinimalMeterStyle) -> Self {
    switch style {
    case .vertical: Self(length: 38, thickness: 6)
    case .horizontal: Self(length: 80, thickness: 6)
    case .ring: Self(length: 32, thickness: 4)
    }
  }

  func normalized(for style: MinimalMeterStyle) -> Self {
    let fallback = Self.defaults(for: style)
    let length = Self.clamp(
      length, to: style == .ring ? 20...80 : 20...160, fallback: fallback.length)
    return Self(
      length: length,
      thickness: Self.clamp(
        thickness, to: 2...(style == .ring ? min(10, floor(length / 6)) : 12),
        fallback: fallback.thickness),
      scale: Self.clamp(scale, to: 0.5...2, fallback: 1))
  }

  private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double)
    -> Double
  {
    min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
  }
}

struct MinimalMeterAppearance: Codable, Equatable, Sendable {
  var style: MinimalMeterStyle = .vertical
  var vertical = MinimalMeterDimensions.defaults(for: .vertical)
  var horizontal = MinimalMeterDimensions.defaults(for: .horizontal)
  var ring = MinimalMeterDimensions.defaults(for: .ring)

  var dimensions: MinimalMeterDimensions {
    get {
      switch style {
      case .vertical: vertical
      case .horizontal: horizontal
      case .ring: ring
      }
    }
    set {
      switch style {
      case .vertical: vertical = newValue
      case .horizontal: horizontal = newValue
      case .ring: ring = newValue
      }
    }
  }

  var normalized: Self {
    var result = self
    result.vertical = vertical.normalized(for: .vertical)
    result.horizontal = horizontal.normalized(for: .horizontal)
    result.ring = ring.normalized(for: .ring)
    return result
  }

  var contentSize: CGSize {
    let value = dimensions.normalized(for: style)
    switch style {
    case .vertical:
      // Reserve the same canvas for one/two quota windows so data refreshes
      // never resize the entry. Defaults retain the original 26 x 44 canvas.
      return CGSize(
        width: max(26, value.thickness * 2 + 14) * value.scale,
        height: (value.length + 6) * value.scale)
    case .horizontal:
      return CGSize(
        width: (value.length + 18) * value.scale,
        height: max(26, value.thickness * 2 + 10) * value.scale)
    case .ring:
      return CGSize(width: value.length * value.scale, height: value.length * value.scale)
    }
  }

  var collapsedSize: CGSize {
    let content = contentSize
    return CGSize(
      width: max(36, ceil(content.width + 10)), height: max(36, ceil(content.height + 10)))
  }
}
