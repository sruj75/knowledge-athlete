import Foundation

private struct AssistantEventDataBox: @unchecked Sendable {
  let value: [String: Any]
  init(_ value: [String: Any]) { self.value = value }
}

/// Coordinates all proactive assistants, distributing frames and managing lifecycle
@MainActor
class AssistantCoordinator {
  static let shared = AssistantCoordinator()

  // MARK: - Properties

  private var assistants: [String: any ProactiveAssistant] = [:]
  private var lastAnalysisTime: [String: Date] = [:]
  private var eventCallback: ((String, [String: Any]) -> Void)?

  // MARK: - Context Tracking (for context switch detection)
  private var lastTrackedApp: String?
  private var lastTrackedWindowTitle: String?
  private var lastTrackedFrame: OwnerBoundCapturedFrame?

  /// Backpressure: track which assistants are currently analyzing a frame.
  /// Prevents Task closures from accumulating CapturedFrame JPEG data when analyze() is slow.
  private var activeAnalysisAuthorization: [String: RuntimeOwnerAuthorizationSnapshot] = [:]
  private var ownerChangeResetCallback: (() -> Void)?

  private init() {}

  // MARK: - Registration

  /// Register an assistant with the coordinator
  /// - Parameter assistant: The assistant to register
  func register<T: ProactiveAssistant>(_ assistant: T) {
    Task {
      let id = await assistant.identifier
      assistants[id] = assistant
      lastAnalysisTime[id] = .distantPast
      log("Registered assistant: \(id)")
    }
  }

  /// Unregister an assistant
  /// - Parameter identifier: The identifier of the assistant to remove
  func unregister(identifier: String) {
    assistants.removeValue(forKey: identifier)
    lastAnalysisTime.removeValue(forKey: identifier)
    log("Unregistered assistant: \(identifier)")
  }

  /// Get all registered assistant identifiers
  var registeredAssistants: [String] {
    Array(assistants.keys)
  }

  /// Get an assistant by identifier
  func assistant(withIdentifier id: String) -> (any ProactiveAssistant)? {
    assistants[id]
  }

  // MARK: - Event Callback

  /// Set the callback for sending events to Flutter
  /// - Parameter callback: Function that takes event type and data
  func setEventCallback(_ callback: ((String, [String: Any]) -> Void)?) {
    self.eventCallback = callback
  }

  func setOwnerChangeResetCallback(_ callback: @escaping () -> Void) {
    ownerChangeResetCallback = callback
  }

  /// Send an event to Flutter
  func sendEvent(type: String, data: [String: Any]) {
    eventCallback?(type, data)
  }

  /// Owner-bound event publication. The check happens on the main actor at the
  /// actual callback boundary, not merely before a task is enqueued.
  func sendEvent(
    type: String,
    data: [String: Any],
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    eventCallback?(type, data)
  }

  // MARK: - Context Switch Detection

  /// Check if the user's context changed (app or normalized window title) and fire
  /// `onContextSwitch` on all assistants if so. Called by the plugin for both app switches
  /// and window title changes — one unified path with one delay mechanism.
  /// - Returns: `true` if a context switch was detected and fired.
  @discardableResult
  func checkContextSwitch(
    newApp: String,
    newWindowTitle: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) -> Bool {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return false }
    guard lastTrackedApp != nil else {
      lastTrackedApp = newApp
      lastTrackedWindowTitle = newWindowTitle
      return false
    }

    let changed = ContextDetection.didContextChange(
      fromApp: lastTrackedApp,
      fromWindowTitle: lastTrackedWindowTitle,
      toApp: newApp,
      toWindowTitle: newWindowTitle
    )
    guard changed else { return false }

    let departingFrame: CapturedFrame? = lastTrackedFrame.flatMap { ownerBoundFrame in
      guard ownerBoundFrame.authorizationSnapshot == authorizationSnapshot,
        RuntimeOwnerIdentity.isAuthorizationCurrent(ownerBoundFrame.authorizationSnapshot)
      else { return nil }
      return ownerBoundFrame.frame
    }
    log(
      "Context switch detected: \(lastTrackedApp ?? "nil") (\(ContextDetection.normalizeWindowTitle(lastTrackedWindowTitle) ?? "nil")) -> \(newApp) (\(ContextDetection.normalizeWindowTitle(newWindowTitle) ?? "nil"))"
    )

    // Update tracking state
    lastTrackedApp = newApp
    lastTrackedWindowTitle = newWindowTitle

    // Fire on all assistants
    for (_, assistant) in assistants {
      Task {
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        await assistant.onContextSwitch(
          departingFrame: departingFrame,
          newApp: newApp,
          newWindowTitle: newWindowTitle,
          authorizationSnapshot: authorizationSnapshot
        )
      }
    }

    return true
  }

  // MARK: - Frame Tracking & Distribution

  /// Keep the latest frame reference fresh (call on every capture, even during delay).
  func trackFrame(
    _ frame: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    lastTrackedFrame = OwnerBoundCapturedFrame(
      frame: frame,
      authorizationSnapshot: authorizationSnapshot)
  }

  var trackedFrameAuthorizationForTests: RuntimeOwnerAuthorizationSnapshot? {
    lastTrackedFrame?.authorizationSnapshot
  }

  /// Distribute a captured frame to all enabled assistants
  /// - Parameter frame: The captured frame to analyze
  func distributeFrame(
    _ frame: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    for (identifier, assistant) in assistants {
      // Backpressure: skip if this assistant is still analyzing a previous frame
      guard activeAnalysisAuthorization[identifier] == nil else { continue }

      let timeSinceLastAnalysis = Date().timeIntervalSince(lastAnalysisTime[identifier] ?? .distantPast)
      activeAnalysisAuthorization[identifier] = authorizationSnapshot

      Task { [weak self] in
        defer {
          Task { @MainActor in
            guard self?.activeAnalysisAuthorization[identifier] == authorizationSnapshot else { return }
            self?.activeAnalysisAuthorization.removeValue(forKey: identifier)
          }
        }

        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

        // Check if assistant is enabled
        guard await assistant.isEnabled else { return }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

        // Check if assistant wants to analyze this frame
        guard
          await assistant.shouldAnalyze(frameNumber: frame.frameNumber, timeSinceLastAnalysis: timeSinceLastAnalysis)
        else {
          return
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

        // Update last analysis time
        await MainActor.run {
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
          self?.lastAnalysisTime[identifier] = Date()
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

        // Analyze and handle result
        if let result = await assistant.analyze(
          frame: frame,
          authorizationSnapshot: authorizationSnapshot)
        {
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
          await assistant.handleResult(
            result,
            authorizationSnapshot: authorizationSnapshot
          ) { [weak self] type, data in
            let dataBox = AssistantEventDataBox(data)
            Task { @MainActor in
              guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
              self?.sendEvent(
                type: type,
                data: dataBox.value,
                authorizationSnapshot: authorizationSnapshot)
            }
          }
        }
      }
    }
  }

  /// Distribute a frame only to assistants that opted into receiving frames during the delay period.
  /// Used for time-sensitive detections like refocus tracking.
  func distributeFrameDuringDelay(
    _ frame: CapturedFrame,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    for (identifier, assistant) in assistants {
      // Backpressure: skip if this assistant is still analyzing a previous frame
      guard activeAnalysisAuthorization[identifier] == nil else { continue }

      let timeSinceLastAnalysis = Date().timeIntervalSince(lastAnalysisTime[identifier] ?? .distantPast)
      activeAnalysisAuthorization[identifier] = authorizationSnapshot

      Task { [weak self] in
        defer {
          Task { @MainActor in
            guard self?.activeAnalysisAuthorization[identifier] == authorizationSnapshot else { return }
            self?.activeAnalysisAuthorization.removeValue(forKey: identifier)
          }
        }

        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        guard await assistant.isEnabled else { return }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        guard await assistant.needsFrameDuringDelay else { return }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        guard
          await assistant.shouldAnalyze(frameNumber: frame.frameNumber, timeSinceLastAnalysis: timeSinceLastAnalysis)
        else {
          return
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

        await MainActor.run {
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
          self?.lastAnalysisTime[identifier] = Date()
        }
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }

        if let result = await assistant.analyze(
          frame: frame,
          authorizationSnapshot: authorizationSnapshot)
        {
          guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
          await assistant.handleResult(
            result,
            authorizationSnapshot: authorizationSnapshot
          ) { [weak self] type, data in
            let dataBox = AssistantEventDataBox(data)
            Task { @MainActor in
              guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
              self?.sendEvent(
                type: type,
                data: dataBox.value,
                authorizationSnapshot: authorizationSnapshot)
            }
          }
        }
      }
    }
  }

  // MARK: - App Switch Handling

  /// Notify all assistants of an app switch (legacy onAppSwitch callback).
  /// Context switch detection is handled separately via `checkContextSwitch`.
  func notifyAppSwitch(
    newApp: String,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    for (_, assistant) in assistants {
      Task {
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        await assistant.onAppSwitch(
          newApp: newApp,
          authorizationSnapshot: authorizationSnapshot)
      }
    }
  }

  /// Clear pending work for all assistants
  func clearAllPendingWork(
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot
  ) {
    guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
    for (_, assistant) in assistants {
      Task {
        guard RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot) else { return }
        await assistant.clearPendingWork(authorizationSnapshot: authorizationSnapshot)
      }
    }
  }

  /// Clear coordinator bookkeeping and every assistant's owner-derived state
  /// before the replacement owner generation becomes visible.
  func resetForOwnerChange() async {
    lastAnalysisTime.removeAll(keepingCapacity: true)
    for identifier in assistants.keys {
      lastAnalysisTime[identifier] = .distantPast
    }
    lastTrackedApp = nil
    lastTrackedWindowTitle = nil
    lastTrackedFrame = nil
    activeAnalysisAuthorization.removeAll()
    ownerChangeResetCallback?()
    for assistant in assistants.values {
      await assistant.resetForOwnerChange()
    }
  }

  // MARK: - Lifecycle

  /// Stop all assistants
  func stopAll() {
    for (_, assistant) in assistants {
      Task {
        await assistant.stop()
      }
    }
  }

  /// Register the default set of assistants
  func registerDefaultAssistants() throws {
    // These will be added as we create the assistants
    // try register(FocusAssistant())
    // try register(TaskAssistant())
  }
}
