import CryptoKit
import Foundation

enum LocalTranscriptFormatter {
  struct NormalizationResult: Equatable, Sendable {
    let segments: [LocalTranscriptSegment]
    let removedSegmentIds: [String]
  }

  private static let sentenceEnders = CharacterSet(charactersIn: ".?!。！？؟۔।॥")

  static func normalize(
    existing: [LocalTranscriptSegment],
    incoming: [LocalTranscriptSegment]
  ) -> NormalizationResult {
    guard !incoming.isEmpty else { return NormalizationResult(segments: existing, removedSegmentIds: []) }

    var retained = existing
    var joined = retained.last.map { [$0] } ?? []
    var removed: [String] = []
    var droppedExistingTail = false

    for newValue in incoming {
      var next = newValue
      if var prior = joined.last {
        let result = merge(prior, next)
        if let mergedPrior = result.0 {
          prior = mergedPrior
          joined[joined.count - 1] = prior
        } else {
          if retained.last?.segmentId == prior.segmentId {
            removed.append(prior.segmentId)
            droppedExistingTail = true
          }
          joined.removeLast()
        }
        if let remainder = result.1 {
          next = remainder
          joined.append(next)
        } else {
          removed.append(newValue.segmentId)
        }
      } else {
        joined.append(next)
      }
    }

    if droppedExistingTail, !retained.isEmpty {
      retained.removeLast()
    } else if let retainedTail = retained.last, joined.first?.segmentId == retainedTail.segmentId {
      retained.removeLast()
    }
    retained.append(contentsOf: joined)
    for index in retained.indices {
      retained[index].text = clean(retained[index].text)
      retained[index].segmentOrder = index
    }
    return NormalizationResult(segments: retained, removedSegmentIds: removed)
  }

  static func format(
    segments: [LocalTranscriptSegment],
    speakerLabels: [Int: String],
    userName: String?,
    includeTimestamps: Bool
  ) -> String {
    let trimmedUserName = userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let resolvedUserName = trimmedUserName.isEmpty ? "User" : trimmedUserName
    let timestampsAreSafe = includeTimestamps && canDisplayTimestamps(segments)

    return segments.map { segment in
      let speaker =
        segment.isUser ? resolvedUserName : (speakerLabels[segment.speakerId] ?? "Speaker \(segment.speakerId)")
      let timestamp =
        timestampsAreSafe
        ? "[\(duration(segment.startTime)) - \(duration(segment.endTime))] " : ""
      return "\(timestamp)\(speaker): \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }.joined(separator: "\n\n")
  }

  static func canDisplayTimestamps(_ segments: [LocalTranscriptSegment]) -> Bool {
    for first in segments.indices {
      for second in segments.indices where second > first {
        if segments[first].startTime > segments[second].endTime
          || segments[first].endTime > segments[second].startTime
        {
          return false
        }
      }
    }
    return true
  }

  static func stableSegmentId(conversationId: String, input: ConversationSegmentInput) -> String {
    if let segmentId = input.segmentId, let uuid = UUID(uuidString: segmentId) {
      return uuid.uuidString.lowercased()
    }
    let providerKey = input.segmentId ?? "\(input.speakerId)|\(input.startTime)|\(input.endTime)|\(input.text)"
    let digest = SHA256.hash(data: Data("\(conversationId)|\(providerKey)".utf8))
    var bytes = Array(digest.prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x50
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let uuid = UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
    return uuid.uuidString.lowercased()
  }

  private static func merge(
    _ prior: LocalTranscriptSegment,
    _ next: LocalTranscriptSegment
  ) -> (LocalTranscriptSegment?, LocalTranscriptSegment?) {
    var a = prior
    var b = next

    if a.speakerId != b.speakerId && !(a.isUser && b.isUser) && !a.text.isEmpty && !b.text.isEmpty,
      let incomplete = lastIncompleteSentence(in: a.text)
    {
      let split = splitFirstSentence(in: b.text)
      if !split.remainder.isEmpty && !split.first.isEmpty && split.first.count < incomplete.value.count {
        a.text = "\(a.text) \(split.first)".trimmingCharacters(in: .whitespacesAndNewlines)
        b.text = split.remainder
        return (a, b)
      }
      if !split.first.isEmpty && !isSentenceComplete(split.first) && split.first.count < incomplete.value.count {
        a.text = "\(a.text) \(split.first)".trimmingCharacters(in: .whitespacesAndNewlines)
        return (a, nil)
      }
      if incomplete.value.count < b.text.trimmingCharacters(in: .whitespacesAndNewlines).count {
        b.text = "\(incomplete.value) \(b.text)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !incomplete.prefix.isEmpty {
          a.text = incomplete.prefix
          a.endTime = min(a.endTime, b.startTime)
          return (a, b)
        }
        return (nil, b)
      }
    }

    let sameSpeaker = a.speakerId == b.speakerId || (a.isUser && b.isUser)
    let closeEnough = b.startTime - a.endTime < 3
    if sameSpeaker && closeEnough && (a.text.count < 125 || !endsSentence(a.text)) {
      a.text += " \(b.text)"
      a.endTime = b.endTime
      if a.translations.isEmpty { a.translations = b.translations }
      return (a, nil)
    }
    if sameSpeaker && !endsSentence(a.text) && startsWithLowercaseLetter(b.text) {
      a.text += " \(b.text)"
      a.endTime = b.endTime
      if a.translations.isEmpty { a.translations = b.translations }
      return (a, nil)
    }
    return (a, b)
  }

  private static func lastIncompleteSentence(in text: String) -> (value: String, prefix: String)? {
    let pieces = sentencePieces(text)
    guard let last = pieces.last, !endsSentence(last) else { return nil }
    return (last, pieces.dropLast().joined(separator: " "))
  }

  private static func splitFirstSentence(in text: String) -> (first: String, remainder: String) {
    let pieces = sentencePieces(text)
    return (pieces.first ?? "", pieces.dropFirst().joined(separator: " "))
  }

  private static func sentencePieces(_ text: String) -> [String] {
    var pieces: [String] = []
    var current = ""
    for scalar in text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
      current.unicodeScalars.append(scalar)
      if sentenceEnders.contains(scalar) {
        let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !piece.isEmpty { pieces.append(piece) }
        current = ""
      }
    }
    let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty { pieces.append(tail) }
    return pieces
  }

  private static func endsSentence(_ text: String) -> Bool {
    guard let scalar = text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last else { return false }
    return sentenceEnders.contains(scalar)
  }

  private static func startsWithLowercaseLetter(_ text: String) -> Bool {
    for scalar in text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
    where CharacterSet.letters.contains(scalar) {
      return CharacterSet.lowercaseLetters.contains(scalar)
    }
    return false
  }

  private static func isSentenceComplete(_ text: String) -> Bool {
    endsSentence(text) && !startsWithLowercaseLetter(text)
  }

  private static func clean(_ text: String) -> String {
    var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
    for punctuation in [",", ".", "?"] {
      result = result.replacingOccurrences(of: " \(punctuation)", with: punctuation)
    }
    return result
  }

  private static func duration(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
  }
}
