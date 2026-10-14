import XCTest

@testable import Omi_Computer

final class ScreenContextTelemetryTests: XCTestCase {
  func testScreenshotSharingPreconditionHasBoundedPhysicalFailure() {
    let metrics = ScreenContextChatCycleMetrics()
    metrics.recordToolRequested("capture_screen")
    metrics.recordToolResult(
      name: "capture_screen",
      output:
        #"EXECUTION_PRECONDITION_FAILED: {"code":"execution_precondition_failed","ok":false,"reason":"screenshot_sharing_disabled","tool":"capture_screen"}"#
    )

    let snapshot = metrics.snapshot()
    XCTAssertTrue(snapshot.screenToolRequested)
    XCTAssertFalse(snapshot.screenToolSucceeded)
    XCTAssertFalse(snapshot.screenToolApprovalRequired)
    XCTAssertEqual(snapshot.screenToolFailureCodes, ["screenshot_sharing_disabled"])
  }

  func testPolicyDeniedScreenshotResultMarksApprovalRequired() {
    let metrics = ScreenContextChatCycleMetrics()
    metrics.recordToolRequested("capture_screen")
    metrics.recordToolResult(
      name: "capture_screen",
      output:
        #"POLICY_DENIED: {"capability":"desktop.context.screenshot_image","code":"approval_required","ok":false,"tool":"capture_screen"}"#
    )

    let snapshot = metrics.snapshot()
    XCTAssertTrue(snapshot.screenToolRequested)
    XCTAssertFalse(snapshot.screenToolSucceeded)
    XCTAssertTrue(snapshot.screenToolApprovalRequired)
    XCTAssertEqual(snapshot.screenToolFailureCodes, ["policy_approval_required"])
  }

  func testPermissionRequiredScreenshotResultMarksPermissionDenied() {
    let metrics = ScreenContextChatCycleMetrics()
    metrics.recordToolRequested("capture_screen")
    metrics.recordToolResult(
      name: "capture_screen",
      output:
        #"PERMISSION_REQUIRED: {"code":"permission_required","next_tool":"request_permission","ok":false,"permission":"screen_recording","tool":"capture_screen"}"#
    )

    let snapshot = metrics.snapshot()
    XCTAssertTrue(snapshot.screenToolRequested)
    XCTAssertFalse(snapshot.screenToolSucceeded)
    XCTAssertFalse(snapshot.screenToolApprovalRequired)
    XCTAssertEqual(snapshot.screenToolFailureCodes, ["permission_denied"])
  }

  func testWorkContextResultMarksUsableScreenContext() {
    let metrics = ScreenContextChatCycleMetrics()
    metrics.recordToolResult(
      name: "get_work_context",
      output:
        #"{"ok":true,"name":"get_work_context","screen_now":{"available":true,"image_bytes":1200,"ocr_preview":"redacted"},"timeline":[{"frames":1}]}"#
    )

    let snapshot = metrics.snapshot()
    XCTAssertTrue(snapshot.screenToolRequested)
    XCTAssertTrue(snapshot.screenToolSucceeded)
    XCTAssertFalse(snapshot.screenToolApprovalRequired)
    XCTAssertEqual(snapshot.screenToolFailureCodes, [])
  }

  func testWorkContextUnavailableKeepsFailureCode() {
    let metrics = ScreenContextChatCycleMetrics()
    metrics.recordToolResult(
      name: "get_work_context",
      output:
        #"{"ok":true,"name":"get_work_context","failure_code":"screenshot_pending","screen_now":{"available":false,"failure_code":"screenshot_pending"},"timeline":[]}"#
    )

    let snapshot = metrics.snapshot()
    XCTAssertTrue(snapshot.screenToolRequested)
    XCTAssertFalse(snapshot.screenToolSucceeded)
    XCTAssertEqual(snapshot.screenToolFailureCodes, ["screenshot_pending"])
  }

  func testWorkContextPermissionDeniedPayloadIsTypedForModels() throws {
    let payload = ScreenContextWorkContextBuilder.permissionDeniedPayload(windowMinutes: 10)
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let output = String(data: data, encoding: .utf8)!

    XCTAssertTrue(output.contains(#""failure_code":"permission_denied""#))
    XCTAssertTrue(output.contains(#""screen_recording":"not_granted""#))
    XCTAssertTrue(output.contains(#""next_tool":"request_permission""#))
    XCTAssertTrue(output.contains(#""type":"screen_recording""#))
    XCTAssertEqual(payload["failure_code"] as? String, "permission_denied")
    XCTAssertEqual(payload["next_tool"] as? String, "request_permission")
    XCTAssertEqual((payload["next_tool_arguments"] as? [String: Any])?["type"] as? String, "screen_recording")

    let facts = ScreenContextToolTelemetry.toolResultFacts(toolName: "get_work_context", output: output)
    XCTAssertEqual(facts?.failureCode, .permissionDenied)
    XCTAssertEqual(facts?.succeeded, false)
  }

  func testTelemetryContextPreservesSharedChatIdentityAcrossTypedAndVoiceSurfaces() {
    let chat = AgentSurfaceReference.mainChat(chatId: "chat-123")
    let typed = ScreenContextTelemetryContext.from(surfaceRef: chat)
    let voice = ScreenContextTelemetryContext.from(surfaceRef: chat.realtimeVoiceCompanion())
    XCTAssertEqual(typed.surface, "main_chat")
    XCTAssertEqual(voice.surface, "realtime_voice")
    XCTAssertEqual(typed.externalRefKind, "chat")
    XCTAssertEqual(voice.externalRefId, typed.externalRefId)
    XCTAssertEqual(voice.externalRefId, "chat-123")
    XCTAssertNil(voice.pillId)
    XCTAssertNil(voice.runId)
  }

  func testAmbientPayloadMinimizesScreenContext() throws {
    let payload: [String: Any] = [
      "ok": true,
      "screen_now": [
        "available": true,
        "source": "live_capture_stale_rewind",
        "latest_capture_age_seconds": 0,
        "app_name": "Safari",
        "window_title": "Docs",
        "ocr_preview": "Sensitive visible text",
        "image_base64": "abc123",
        "image_bytes": 12345,
      ],
      "timeline": [
        ["app_name": "Safari"]
      ],
    ]

    let ambient = ScreenContextWorkContextBuilder.ambientPayload(from: payload)
    let data = try JSONSerialization.data(withJSONObject: ambient, options: [.sortedKeys])
    let output = String(data: data, encoding: .utf8)!

    XCTAssertTrue(output.contains(#""ambient":true"#))
    XCTAssertTrue(output.contains(#""app_name":"Safari""#))
    XCTAssertTrue(output.contains(#""source":"live_capture_stale_rewind""#))
    XCTAssertFalse(output.contains("Sensitive visible text"))
    XCTAssertFalse(output.contains("abc123"))
    XCTAssertFalse(output.contains("image_bytes"))
    XCTAssertTrue(output.contains(#""timeline_count":1"#))
  }

  func testWorkContextUsesFreshCaptureWhenFinalizedFrameIsStale() {
    XCTAssertFalse(
      ScreenContextWorkContextBuilder.shouldUseFreshCapture(
        screenNow: ["available": true],
        latestCaptureAgeSeconds: 60
      )
    )
    XCTAssertTrue(
      ScreenContextWorkContextBuilder.shouldUseFreshCapture(
        screenNow: ["available": true],
        latestCaptureAgeSeconds: 61
      )
    )
    XCTAssertTrue(
      ScreenContextWorkContextBuilder.shouldUseFreshCapture(
        screenNow: ["available": false],
        latestCaptureAgeSeconds: 0
      )
    )
    XCTAssertTrue(
      ScreenContextWorkContextBuilder.shouldUseFreshCapture(
        screenNow: ["available": true],
        latestCaptureAgeSeconds: nil
      )
    )
  }

  func testVoiceWorkContextUsesShorterFreshnessBudget() {
    XCTAssertFalse(
      ScreenContextWorkContextBuilder.shouldUseFreshCapture(
        screenNow: ["available": true],
        latestCaptureAgeSeconds: ScreenContextWorkContextBuilder.voiceTurnStaleCaptureThresholdSeconds,
        staleThresholdSeconds: ScreenContextWorkContextBuilder.voiceTurnStaleCaptureThresholdSeconds
      )
    )
    XCTAssertTrue(
      ScreenContextWorkContextBuilder.shouldUseFreshCapture(
        screenNow: ["available": true],
        latestCaptureAgeSeconds: ScreenContextWorkContextBuilder.voiceTurnStaleCaptureThresholdSeconds + 1,
        staleThresholdSeconds: ScreenContextWorkContextBuilder.voiceTurnStaleCaptureThresholdSeconds
      )
    )
  }

  func testExplicitCurrentScreenPayloadOnlyAcceptsTurnScopedAttachedImage() throws {
    let formatter = ISO8601DateFormatter()
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    let delivered = ScreenContextWorkContextBuilder.explicitCurrentScreenPayload(
      screenRecordingGranted: true,
      imageAttached: true,
      capturedAt: capturedAt,
      formatter: formatter
    )
    let unavailable = ScreenContextWorkContextBuilder.explicitCurrentScreenPayload(
      screenRecordingGranted: true,
      imageAttached: false,
      capturedAt: capturedAt,
      formatter: formatter
    )
    let deliveredJSON = String(
      data: try JSONSerialization.data(withJSONObject: delivered, options: [.sortedKeys]),
      encoding: .utf8
    )!

    XCTAssertTrue(deliveredJSON.contains(#""source":"turn_scoped_live_capture""#))
    XCTAssertEqual(
      ((delivered["screen_now"] as? [String: Any])?["image_delivered_to_model"] as? NSNumber)?.boolValue,
      true
    )
    XCTAssertFalse(deliveredJSON.contains("Rewind"))
    XCTAssertEqual((unavailable["screen_now"] as? [String: Any])?["available"] as? Bool, false)
    XCTAssertEqual(unavailable["failure_code"] as? String, "image_unavailable")
  }

  func testPTTTranscriptVocabularyUsesOnlyTurnScopedOCRAndExplicitVocabulary() {
    let snapshot = PTTContextVocabularyProvider.snapshot(
      capturedAt: Date(timeIntervalSince1970: 1_000),
      settingsVocabulary: ["Omi"],
      immediateOCRText: "Codex is open on the current screen")

    XCTAssertEqual(snapshot.sourceCount, 1)
    XCTAssertTrue(snapshot.keywords.contains("Omi"))
    XCTAssertTrue(snapshot.keywords.contains("Codex"))
    XCTAssertFalse(snapshot.keywords.contains("Cursor"))
  }

  func testStaleWorkContextDropsScreenNowWhenFreshCaptureFails() throws {
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Chat/ScreenContextTelemetry.swift"),
      encoding: .utf8
    )

    XCTAssertTrue(source.contains("failureCode = .imageUnavailable"))
    XCTAssertTrue(source.contains(#""available": false"#))
    XCTAssertTrue(
      source.contains("Latest finalized work-context frame was older than \\(staleThresholdSeconds) seconds"))
    XCTAssertTrue(source.contains(#""stale_inspection_ignored""#))
    XCTAssertFalse(source.contains(#""image_base64": data.base64EncodedString()"#))
    XCTAssertTrue(source.contains(#""raw_image_tool": "capture_screen""#))
  }

  func testChatMessageSentHasNoDeletedAppContextProperty() throws {
    let sourcesDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources")

    let postHog = try String(
      contentsOf: sourcesDir.appendingPathComponent("PostHogManager.swift"),
      encoding: .utf8
    )
    XCTAssertFalse(postHog.contains(#""has_context""#))
    XCTAssertFalse(postHog.contains(#""has_selected_app_context""#))
  }

  func testScreenInterestDetectorCatchesExplicitAndDeicticRequests() {
    XCTAssertTrue(ScreenContextInterestDetector.isScreenContextRequest("Can you see my screen?"))
    XCTAssertTrue(ScreenContextInterestDetector.isScreenContextRequest("Debug this error"))
    XCTAssertFalse(ScreenContextInterestDetector.isScreenContextRequest("What did I do yesterday?"))
  }

  func testScreenContextAutoIncludePolicyCoversFloatingAndMainTurns() {
    XCTAssertEqual(
      ScreenContextAutoIncludePolicy.reason(
        userText: "can you see my screen?",
        systemPromptStyle: .main,
        turnOwner: .mainChat
      ),
      .explicitScreenRequest
    )
    XCTAssertEqual(
      ScreenContextAutoIncludePolicy.reason(
        userText: "which one",
        systemPromptStyle: .floating,
        turnOwner: .floatingDefault
      ),
      .ambientSurfaceContext
    )
    XCTAssertTrue(
      ScreenContextAutoIncludePolicy.shouldInclude(
        userText: "which one",
        systemPromptStyle: .floating,
        turnOwner: .floatingDefault
      ))
    XCTAssertTrue(
      ScreenContextAutoIncludePolicy.shouldInclude(
        userText: "debug this error",
        systemPromptStyle: .main,
        turnOwner: .mainChat
      ))
    XCTAssertFalse(
      ScreenContextAutoIncludePolicy.shouldInclude(
        userText: "what did I do yesterday?",
        systemPromptStyle: .main,
        turnOwner: .mainChat
      ))
  }

  func testOnboardingFloatingTurnsAreExplicitScreenRequests() {
    // The demo's suggested query has no screen-cue words; during onboarding a
    // floating turn must still attempt a real capture so failures surface.
    XCTAssertEqual(
      ScreenContextAutoIncludePolicy.reason(
        userText: "Which computer should I buy?",
        systemPromptStyle: .floating,
        turnOwner: .floatingDefault,
        onboardingActive: true
      ),
      .explicitScreenRequest
    )
    XCTAssertEqual(
      ScreenContextAutoIncludePolicy.reason(
        userText: "Which computer should I buy?",
        systemPromptStyle: .floating,
        turnOwner: .floatingDefault,
        onboardingActive: false
      ),
      .ambientSurfaceContext
    )
    // Onboarding must not change non-floating owners.
    XCTAssertNil(
      ScreenContextAutoIncludePolicy.reason(
        userText: "hello",
        systemPromptStyle: .main,
        turnOwner: .mainChat,
        onboardingActive: true
      ))
  }

  func testCaptureFailureGuidanceTellsUserToRelaunch() {
    let payload = ScreenContextWorkContextBuilder.explicitCurrentScreenPayload(
      screenRecordingGranted: true,
      imageAttached: false
    )
    let guidance = payload["guidance"] as? String ?? ""
    XCTAssertTrue(guidance.contains("quit and reopen Intentive"))
  }

  func testAmbientPermissionUnavailablePayloadIsConditionalOnScreenDependence() {
    let payload = ScreenContextWorkContextBuilder.ambientPermissionUnavailablePayload()
    let guidance = payload["guidance"] as? String ?? ""
    XCTAssertTrue(guidance.contains("enable Screen Recording"))
    XCTAssertTrue(guidance.contains("ONLY if"))
    let permission = payload["permission"] as? [String: String]
    XCTAssertEqual(permission?["screen_recording"], "not_granted")
  }
}
