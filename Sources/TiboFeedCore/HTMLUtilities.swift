import Foundation

enum HTMLUtilities {
  static func matches(_ pattern: String, in text: String) -> [[String]] {
    guard
      let regex = try? NSRegularExpression(
        pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: range).map { match in
      (0..<match.numberOfRanges).map { index in
        let capture = match.range(at: index)
        guard capture.location != NSNotFound, let range = Range(capture, in: text) else {
          return ""
        }
        return String(text[range])
      }
    }
  }

  static func first(_ pattern: String, in text: String) -> [String]? {
    matches(pattern, in: text).first
  }

  static func plainText(_ html: String) -> String {
    let withoutTags = html.replacingOccurrences(
      of: "<[^>]+>", with: " ", options: .regularExpression)
    return decodeEntities(withoutTags)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func decodeEntities(_ text: String) -> String {
    var value =
      text
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#34;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&#x27;", with: "'")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&nbsp;", with: " ")

    let patterns = ["&#([0-9]+);", "&#x([0-9a-fA-F]+);"]
    for (index, pattern) in patterns.enumerated() {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let source = value
      let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        .reversed()
      for match in matches {
        guard let whole = Range(match.range(at: 0), in: source),
          let numberRange = Range(match.range(at: 1), in: source),
          let scalarValue = UInt32(source[numberRange], radix: index == 0 ? 10 : 16),
          let scalar = UnicodeScalar(scalarValue)
        else { continue }
        value.replaceSubrange(whole, with: String(Character(scalar)))
      }
    }
    return value
  }
}
