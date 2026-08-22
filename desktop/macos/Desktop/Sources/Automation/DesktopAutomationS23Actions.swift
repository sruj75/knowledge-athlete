import Foundation

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
    guard let authorization = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else {
      return ["status": "owner_unavailable"]
    }
    let suite = "omi.e2e.fair-use-warning.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
      return ["status": "defaults_unavailable"]
    }
    defer { defaults.removePersistentDomain(forName: suite) }
    let presenter = FairUseWarningNotificationPresenter(defaults: defaults)
    let receipt = FairUseClassificationReceipt(
      reviewId: "11111111-1111-4111-8111-111111111111",
      accepted: true,
      idempotent: false,
      action: "warning",
      stage: "warning",
      caseRef: "FU-E2E123")
    let presentation = FairUseWarningPresentation.from(receipt)
    let firstPresented = await presenter.present(receipt, authorization: authorization)
    let duplicatePresented = await presenter.present(receipt, authorization: authorization)
    let relaunchedPresenter = FairUseWarningNotificationPresenter(defaults: defaults)
    let relaunchedDuplicatePresented = await relaunchedPresenter.present(
      receipt, authorization: authorization)
    return [
      "status": firstPresented ? "presented" : "delivery_rejected",
      "first_presented": firstPresented ? "true" : "false",
      "duplicate_suppressed": (firstPresented && !duplicatePresented && !relaunchedDuplicatePresented)
        ? "true" : "false",
      "delivery_count": firstPresented ? "1" : "0",
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
