import Foundation

private actor S23FairUseEvidenceReader: FairUseEvidenceReading {
  func fairUseEvidence(
    now: Date,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> [FairUseConversationEvidence] { [] }
}

private actor S23FairUseSubmitter: FairUseReviewSubmitting {
  private(set) var submissions = 0
  let receipt: FairUseClassificationReceipt

  init(receipt: FairUseClassificationReceipt) {
    self.receipt = receipt
  }

  func classifyFairUseReview(
    reviewId: String,
    conversations: [FairUseConversationEvidence],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) async throws -> FairUseClassificationReceipt {
    submissions += 1
    return receipt
  }
}

extension DesktopAutomationActionRegistry {
  func registerS23Actions() {
    registerFairUseLocalEnforcementProbe()
    registerLocalUserDataExportAction()
  }

  private func registerFairUseLocalEnforcementProbe() {
    register(
      name: "fair_use_local_enforcement_probe",
      summary:
        "Run content-redacted fair-use admission, warning, owner-local evidence, or managed-cloud handoff probes. Non-prod only.",
      params: ["phase"],
      category: "coordinator",
      surfaces: ["ambient_transcription"],
      safety: "non_production_probe",
      sideEffects: [
        "may read bounded owner-local conversation metadata",
        "may present one owner-local fair-use warning",
        "creates then finalizes one empty owner-local harness conversation",
      ]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "fair_use_local_enforcement_probe is disabled on production bundles"]
      }
      let phase = (params["phase"] ?? "handoff").lowercased()
      switch phase {
      case "admission":
        return await FairUseAutomationProbe.rejectedExpiredAdmission()
      case "warning":
        return await Self.warningProbeResult()
      case "evidence":
        return await Self.evidenceProbeResult()
      case "handoff":
        guard let appState = AppState.current else { return ["error": "app state unavailable"] }
        return await appState.automationExerciseFairUseManagedCloudHandoff()
      default:
        return ["error": "phase must be admission, warning, evidence, or handoff"]
      }
    }
  }

  private static func warningProbeResult() async -> [String: String] {
    guard let appState = AppState.current,
      let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot()
    else {
      return ["status": "owner_unavailable"]
    }
    let suite = "omi.e2e.fair-use-warning.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
      return ["status": "defaults_unavailable"]
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let receipt = FairUseClassificationReceipt(
      reviewId: "11111111-1111-4111-8111-111111111111",
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-E2E123")
    let presenter = FairUseWarningNotificationPresenter(defaults: defaults)
    let submitter = S23FairUseSubmitter(receipt: receipt)
    let coordinator = FairUseReviewCoordinator(
      storage: S23FairUseEvidenceReader(),
      submitter: submitter,
      presentReceipt: { receipt, authorization in
        await presenter.accept(receipt, authorization: authorization)
      })
    let previousCoordinator = appState.fairUseReviewCoordinator
    appState.fairUseReviewCoordinator = coordinator
    defer { appState.fairUseReviewCoordinator = previousCoordinator }
    let now = Date()
    let request = FairUseReviewRequest(
      reviewId: receipt.reviewId,
      trigger: "automation_probe",
      windowSpeechMs: ["daily_ms": 7_200_001],
      thresholdsMs: ["daily_ms": 7_200_000],
      classifierContract: "gemini/gemini-3.7-flash:prompt-v2",
      requestedAt: now,
      expiresAt: now.addingTimeInterval(300))
    let presentation = FairUseWarningPresentation.from(receipt)
    await appState.handleListenEvent(.fairUseReviewRequested(request))
    let firstStatus = presenter.deliveryStatus(for: receipt, ownerID: authorization.ownerID)
    await appState.handleListenEvent(.fairUseReviewRequested(request))
    let relaunchedPresenter = FairUseWarningNotificationPresenter(defaults: defaults)
    let replayDeliveryCount = await relaunchedPresenter.replayPending(authorization: authorization)
    let finalStatus = relaunchedPresenter.deliveryStatus(
      for: receipt, ownerID: authorization.ownerID)
    let submissions = await submitter.submissions
    let deliveryStateTruthful =
      firstStatus.inAppPresented
      && (finalStatus.systemBannerDelivered != finalStatus.pendingReplay)
    let replayStateTruthful =
      FairUseWarningAutomationAcceptance.replayStateIsTruthful(
        first: firstStatus,
        final: finalStatus,
        replayDeliveryCount: replayDeliveryCount)
    return [
      "status": finalStatus.systemBannerDelivered ? "presented" : "pending_replay",
      "receipt_owned": (finalStatus.systemBannerDelivered || finalStatus.pendingReplay) ? "true" : "false",
      "first_in_app_presented": firstStatus.inAppPresented ? "true" : "false",
      "system_banner_delivered": finalStatus.systemBannerDelivered ? "true" : "false",
      "pending_replay": finalStatus.pendingReplay ? "true" : "false",
      "replay_delivery_count": "\(replayDeliveryCount)",
      "delivery_state_truthful": deliveryStateTruthful ? "true" : "false",
      "replay_state_truthful": replayStateTruthful ? "true" : "false",
      "duplicate_event_suppressed": submissions == 1 ? "true" : "false",
      "production_event_seam": "true",
      "fixed_title": presentation?.title == "Fair Use Notice" ? "true" : "false",
      "case_reference_present": presentation?.message.contains("FU-E2E123") == true ? "true" : "false",
      "fcm_attempted": "false",
    ]
  }

  private static func evidenceProbeResult() async -> [String: String] {
    guard let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      return [
        "status": "owner_unavailable",
        "maximum_rows": "30",
        "content_fields_exposed": "false",
      ]
    }
    do {
      let evidence = try await TranscriptionStorage.shared.fairUseEvidence(
        now: Date(), authorizationSnapshot: authorization)
      let localRows = try await TranscriptionStorage.shared.conversationPage(
        query: .all, offset: 0, limit: 200, authorizationSnapshot: authorization)
      let canonicalIDs = Set(localRows.map(\.id))
      return [
        "status": "loaded",
        "evidence_count": "\(evidence.count)",
        "maximum_rows": "30",
        "within_row_limit": evidence.count <= 30 ? "true" : "false",
        "request_ids_are_opaque": evidence.allSatisfy { !canonicalIDs.contains($0.conversationId) }
          ? "true" : "false",
        "authorization_current": RuntimeOwnerIdentity.isAuthorizationCurrent(authorization) ? "true" : "false",
        "content_fields_exposed": "false",
      ]
    } catch {
      return [
        "status": "read_rejected",
        "maximum_rows": "30",
        "content_fields_exposed": "false",
      ]
    }
  }

  private func registerLocalUserDataExportAction() {
    register(
      name: "export_my_data",
      summary:
        "Export the active owner's complete local data through the production exporter, validate the JSON, then remove the disposable harness file. Non-prod only.",
      category: "account",
      surfaces: ["settings_account"],
      safety: "non_production_temporary_file",
      sideEffects: ["writes and removes one JSON file under the macOS temporary directory"]
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "export_my_data is disabled on production bundles"]
      }
      guard let ownerID = RuntimeOwnerIdentity.currentOwnerId() else {
        return ["error": "no active local owner"]
      }

      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("omi-export-harness-\(UUID().uuidString)", isDirectory: true)
      let destination = directory.appendingPathComponent("omi-data-export.json")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }

      try await LocalUserDataExport().export(ownerID: ownerID, to: destination)
      let data = try Data(contentsOf: destination)
      guard
        let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let schemaVersion = document["schema_version"] as? NSNumber
      else {
        throw DesktopAutomationActionError.invalidParams("local export did not produce schema JSON")
      }

      func arrayCount(_ key: String) -> String {
        "\((document[key] as? [Any])?.count ?? -1)"
      }

      return [
        "saved": "true",
        "schema_version": schemaVersion.stringValue,
        "conversations": arrayCount("conversations"),
        "memories": arrayCount("memories"),
        "tasks": arrayCount("tasks"),
        "goals": arrayCount("goals"),
        "chats": arrayCount("chat_history"),
        "focus_records": arrayCount("focus_data"),
        "settings_present": document["settings"] is [String: Any] ? "true" : "false",
        "server_requested": "false",
        "temporary_file": "true",
      ]
    }
  }
}

enum FairUseWarningAutomationAcceptance {
  static func replayStateIsTruthful(
    first: FairUseWarningDeliveryStatus,
    final: FairUseWarningDeliveryStatus,
    replayDeliveryCount: Int
  ) -> Bool {
    if final.systemBannerDelivered {
      return replayDeliveryCount == (first.systemBannerDelivered ? 0 : 1)
    }
    return final.pendingReplay && replayDeliveryCount == 0
  }
}
