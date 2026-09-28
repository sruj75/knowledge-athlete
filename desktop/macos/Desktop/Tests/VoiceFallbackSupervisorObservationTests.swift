import VoiceTurnDomain
import XCTest

@testable import Omi_Computer

@MainActor
private final class FallbackVoiceScheduler: VoiceTurnDeadlineScheduling {
  private final class Cancellation: VoiceTurnDeadlineCancellation {
    func cancel() {}
  }

  func schedule(
    deadline: VoiceTurnDeadline, after interval: TimeInterval, action: @escaping @MainActor () -> Void
  ) -> any VoiceTurnDeadlineCancellation {
    Cancellation()
  }
}

@MainActor
private final class FallbackSupervisorHarness {
  let authority = RuntimeOwnerAuthorizationAuthority()
  var owner: RuntimeOwnerAuthorizationSnapshot
  let defaults: UserDefaults
  var requests: [SupervisorEvaluationRequest] = []

  init() throws {
    defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    owner = try XCTUnwrap(authority.capture(ownerID: "fallback-owner", expectedOwnerID: nil))
  }

  lazy var supervisor = SupervisorService(
    defaults: defaults, currentOwner: { self.owner },
    ownerIsCurrent: { self.authority.isCurrent($0, ownerID: "fallback-owner") },
    evaluate: { request, _ in
      self.requests.append(request)
      return .init(
        decisionID: UUID().uuidString, observationID: request.observationID,
        sessionID: request.sessionID, contextEpoch: request.contextEpoch,
        action: .wait, note: nil,
        prompt: .init(text: "", name: "supervisor", version: "test", source: "fallback"),
        outcome: "completed")
    },
    loadMemory: { _ in .empty }, deliver: { _ in },
    decisionStarted: { _ in }, recordDecision: { _, _, _ in },
    automaticallySchedule: false)

  lazy var coordinator = VoiceTurnCoordinator(
    scheduler: FallbackVoiceScheduler(), supervisor: supervisor,
    requiresAuthenticatedOwner: true, ownerIDProvider: { "fallback-owner" },
    ownerIsCurrent: { _ in self.authority.isCurrent(self.owner, ownerID: "fallback-owner") })

  func startReply(duringRecording: () -> Void = {}) throws -> (VoiceNonHubCompletionToken, VoiceOutputLease) {
    let turnID = coordinator.begin(intent: .hold)
    XCTAssertEqual(coordinator.activeTurn?.phase, .recording)
    duringRecording()
    coordinator.publish(.selectRoute(turnID: turnID, route: .managedBatch))
    coordinator.publish(.finalize(turnID: turnID))
    coordinator.publish(.transcriptionStarted(turnID: turnID))
    coordinator.publish(.transcriptionFinal(turnID: turnID, text: "Ask about the missing check."))
    let identity = try XCTUnwrap(coordinator.activeTurn?.providerEffectIdentity)
    coordinator.publish(
      .providerResponseStartedScoped(
        turnID: turnID, identity: identity, sessionID: nil, responseID: nil))
    guard case .acquired(let lease) = coordinator.acquireOutput(.selectedVoiceFallback, turnID: turnID) else {
      throw XCTUnwrapFailure.missingLease
    }
    return (try XCTUnwrap(coordinator.nonHubCompletionToken(for: turnID)), lease)
  }

  private enum XCTUnwrapFailure: Error { case missingLease }
}

@MainActor
final class VoiceFallbackSupervisorObservationTests: XCTestCase {
  private let conversation = VoiceNonHubConversation(
    userText: "Ask about the missing check.", assistantText: "Which check is still missing?")

  func testAcceptedFallbackExchangeReachesSupervisorAndCompletesOnlyAfterPlaybackDrains() async throws {
    let h = try FallbackSupervisorHarness()
    defer {
      h.coordinator.reset()
      h.supervisor.endSession()
    }
    let (token, lease) = try h.startReply()

    XCTAssertTrue(
      h.coordinator.completeNonHubProvider(
        token, outcome: .journalAccepted,
        conversation: .init(
          userText: "Ask about the missing check.", assistantText: "Which check is still missing?")))
    await h.supervisor.evaluatePendingObservation()
    let generated = try XCTUnwrap(h.requests.last)
    XCTAssertEqual(generated.conversation.map(\.role), ["user", "assistant"])
    XCTAssertEqual(
      generated.conversation.map(\.text), ["Ask about the missing check.", "Which check is still missing?"])
    XCTAssertTrue(generated.conversation.allSatisfy { $0.turnID == token.turnID.description && $0.outcome == nil })
    XCTAssertNotNil(h.coordinator.activeTurnID, "A generated reply is still playing")

    XCTAssertTrue(h.coordinator.releaseOutput(lease))
    await h.supervisor.evaluatePendingObservation()
    let completed = try XCTUnwrap(h.requests.last)
    XCTAssertEqual(completed.conversation.map(\.outcome), ["completed", "completed"])
    XCTAssertEqual(h.coordinator.model.lastTerminal?.reason, .success)
  }

  func testInterruptedFallbackReplyUpdatesExistingPairWithoutClaimingDelivery() async throws {
    let h = try FallbackSupervisorHarness()
    defer {
      h.coordinator.reset()
      h.supervisor.endSession()
    }
    let (token, _) = try h.startReply()
    XCTAssertTrue(h.coordinator.completeNonHubProvider(token, outcome: .journalAccepted, conversation: conversation))
    h.coordinator.publish(.interrupt(turnID: token.turnID))
    await h.supervisor.evaluatePendingObservation()
    XCTAssertEqual(h.requests.last?.conversation.map(\.outcome), ["cancelled", "cancelled"])
    XCTAssertFalse(h.coordinator.hasDeliveredVoiceOutput(turnID: token.turnID))
  }

  func testSupervisorSessionEndingDuringRecordingDoesNotReattributeReplyAtTokenCreation() async throws {
    let h = try FallbackSupervisorHarness()
    defer {
      h.coordinator.reset()
      h.supervisor.endSession()
    }
    let (token, lease) = try h.startReply(duringRecording: { h.supervisor.endSession() })
    XCTAssertTrue(h.coordinator.completeNonHubProvider(token, outcome: .journalAccepted, conversation: conversation))
    XCTAssertTrue(h.coordinator.releaseOutput(lease))
    await h.supervisor.evaluatePendingObservation()
    XCTAssertTrue(h.requests.isEmpty, "The physical turn belongs to the session in which capture began")
  }

  func testSupervisorSessionEndingDuringRequestDropsAcceptedReply() async throws {
    let h = try FallbackSupervisorHarness()
    defer {
      h.coordinator.reset()
      h.supervisor.endSession()
    }
    let (token, lease) = try h.startReply()
    h.supervisor.endSession()
    XCTAssertTrue(h.coordinator.completeNonHubProvider(token, outcome: .journalAccepted, conversation: conversation))
    XCTAssertTrue(h.coordinator.releaseOutput(lease))
    await h.supervisor.evaluatePendingObservation()
    XCTAssertTrue(h.requests.isEmpty)
  }

  func testSameOwnerReauthorizationCannotReviveObservationAdmission() async throws {
    let h = try FallbackSupervisorHarness()
    defer {
      h.coordinator.reset()
      h.supervisor.endSession()
    }
    let (token, lease) = try h.startReply()
    h.authority.beginTransition()
    h.authority.endTransition(ownerID: "fallback-owner")
    h.owner = try XCTUnwrap(h.authority.capture(ownerID: "fallback-owner", expectedOwnerID: nil))
    XCTAssertTrue(h.coordinator.completeNonHubProvider(token, outcome: .journalAccepted, conversation: conversation))
    XCTAssertTrue(h.coordinator.releaseOutput(lease))
    await h.supervisor.evaluatePendingObservation()
    XCTAssertTrue(h.requests.isEmpty)
  }

  func testUnacceptedJournalAndLateCancelledCompletionDoNotObserveFutureAssistantText() async throws {
    let h = try FallbackSupervisorHarness()
    defer {
      h.coordinator.reset()
      h.supervisor.endSession()
    }
    let (failedToken, failedLease) = try h.startReply()
    XCTAssertTrue(
      h.coordinator.completeNonHubProvider(failedToken, outcome: .journalFailed, conversation: conversation))
    _ = h.coordinator.releaseOutput(failedLease)
    await h.supervisor.evaluatePendingObservation()
    XCTAssertTrue(h.requests.isEmpty)

    let (cancelledToken, _) = try h.startReply()
    h.coordinator.publish(.interrupt(turnID: cancelledToken.turnID))
    XCTAssertFalse(
      h.coordinator.completeNonHubProvider(cancelledToken, outcome: .journalAccepted, conversation: conversation))
    await h.supervisor.evaluatePendingObservation()
    XCTAssertTrue(h.requests.isEmpty)
  }
}
