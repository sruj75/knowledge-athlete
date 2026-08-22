import XCTest

@testable import Omi_Computer

@MainActor
final class PTTBatchLanguagePolicyTests: XCTestCase {
  func testDetectedVoiceLanguageWinsAndEmptyResultRetriesMultiExactlyOnce() async throws {
    var languages: [String] = []
    var fallbacks: [(String, String, DesktopFallbackOutcome)] = []
    let result = try await PTTBatchTranscriptionPolicy.transcribe(
      audioData: Data([0, 1]),
      voiceLanguages: ["ru", "en-US"],
      verdictCode: "en",
      contextKeywords: ["Hypermind"],
      isAuthorized: { true },
      recordLanguageFallback: { fallbacks.append(($0, $1, $2)) }
    ) { _, language, keywords in
      languages.append(language)
      XCTAssertEqual(keywords, ["Hypermind"])
      return .init(
        transcript: languages.count == 1 ? nil : "hello",
        provider: "test",
        model: "test")
    }

    XCTAssertEqual(languages, ["en-US", "multi"])
    XCTAssertEqual(fallbacks.count, 1)
    XCTAssertEqual(fallbacks.first?.0, "en-US")
    XCTAssertEqual(fallbacks.first?.1, "multi")
    XCTAssertEqual(fallbacks.first?.2, .recovered)
    XCTAssertEqual(result.transcript, "hello")
  }

  func testSingleConfiguredVoiceLanguageDoesNotReadAmbientTranscriptionSettings() async throws {
    var languages: [String] = []
    _ = try await PTTBatchTranscriptionPolicy.transcribe(
      audioData: Data([0, 1]),
      voiceLanguages: ["pt-BR"],
      verdictCode: nil,
      contextKeywords: [],
      isAuthorized: { true }
    ) { _, language, _ in
      languages.append(language)
      return .init(transcript: "ola", provider: nil, model: nil)
    }

    XCTAssertEqual(languages, ["pt-BR"])
  }

  func testUnconfiguredOrAmbiguousVoiceLanguagesUseMultilingualModeWithoutRetry() async throws {
    for languages in [[], ["ru", "en"]] {
      var attempts: [String] = []
      _ = try await PTTBatchTranscriptionPolicy.transcribe(
        audioData: Data([0, 1]),
        voiceLanguages: languages,
        verdictCode: nil,
        contextKeywords: [],
        isAuthorized: { true }
      ) { _, language, _ in
        attempts.append(language)
        return .init(transcript: nil, provider: nil, model: nil)
      }
      XCTAssertEqual(attempts, ["multi"])
    }
  }

  func testOwnerLossAfterSuspensionRejectsTheResultWithoutRetry() async {
    var authorized = true
    var attempts = 0

    do {
      _ = try await PTTBatchTranscriptionPolicy.transcribe(
        audioData: Data([0, 1]),
        voiceLanguages: ["ru"],
        verdictCode: "ru",
        contextKeywords: [],
        isAuthorized: { authorized }
      ) { _, _, _ in
        attempts += 1
        authorized = false
        return .init(transcript: nil, provider: nil, model: nil)
      }
      XCTFail("Expected owner loss to cancel publication")
    } catch is CancellationError {
      XCTAssertEqual(attempts, 1)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testContextSnapshotSeparatesExplicitVocabularyFromScreenCorrectionTerms() {
    let snapshot = PTTContextVocabularyProvider.snapshot(
      capturedAt: Date(timeIntervalSince1970: 1),
      settingsVocabulary: ["Hypermind"],
      immediateOCRText: "Private screen words")

    XCTAssertEqual(snapshot.backendKeywords, ["Hypermind"])
    XCTAssertTrue(snapshot.keywords.contains("Hypermind"))
    XCTAssertTrue(snapshot.keywords.contains("Private"))
    XCTAssertTrue(snapshot.keywords.contains("words"))
    XCTAssertEqual(
      PTTBatchTranscriptionPolicy.backendContextKeywords(
        contextSnapshot: nil,
        settingsVocabulary: ["Hypermind"]),
      ["Hypermind"],
      "slow OCR must not suppress explicit Settings vocabulary")
    XCTAssertEqual(
      PTTBatchTranscriptionPolicy.backendContextKeywords(
        contextSnapshot: snapshot,
        settingsVocabulary: ["changed-after-capture"]),
      ["Hypermind"])
  }
}
