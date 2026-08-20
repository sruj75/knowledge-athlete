import type {
  AdapterAttemptResult,
  AdapterBindingHandle,
  CancelDispatchResult,
  OpenedBinding,
  RuntimeAdapter,
} from "../adapters/interface.js";
import type { OutboundMessage } from "../protocol.js";
import { AdapterRegistry } from "./adapter-registry.js";
import { AdapterRuntimeError, failureFromError } from "./failures.js";
import {
  clearOwnerSurfaceState,
  resolveSurfaceSession,
  type ResolveSurfaceSessionInput,
  type ResolveSurfaceSessionResult,
} from "./surface-session.js";
import type {
  AdapterBinding,
  AgentArtifact,
  AgentDelegation,
  AgentRun,
  AgentSession,
  AgentStore,
  AgentGrant,
  NewAgentArtifact,
  NewAgentGrant,
  RunAttempt,
  RunStatus,
  DelegationStatus,
  DesktopAttentionOverride,
  NewDesktopCoordinatorDispatch,
  DesktopCoordinatorDispatch,
  NewDesktopContextPacket,
} from "./types.js";
import { buildDesktopActionQueue, type DesktopActionQueueItem } from "./desktop-action-queue.js";
import { buildDesktopContextPacket, type BuiltDesktopContextPacket, type DesktopContextPacketBuildInput } from "./desktop-context-packet.js";
import {
  DesktopIntentRouter,
  type DesktopIntentEffectKind,
  type DesktopIntentRoute,
  type DesktopIntentRouteAuthority,
  type DesktopIntentRouteRequest,
  type DesktopIntentSyntaxFacts,
  type DesktopIntentTarget,
} from "./desktop-intent-router.js";
import { OmiArtifactStorage } from "./artifact-storage.js";
import { writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import {
  ACTIVE_STATUSES,
  TERMINAL_STATUSES,
  DEFAULT_DELEGATION_MAX_DEPTH,
  HARD_DELEGATION_MAX_DEPTH,
  DEFAULT_DELEGATION_MAX_BUDGET_USD,
  HARD_DELEGATION_MAX_BUDGET_USD,
  requiresVerifiedContextDispatch,
  bindingMetadata,
  stableHash,
  stableJsonStringify,
  parseJsonObject,
  placeholders,
  isStaleBindingError,
  messageFrom,
  boundedLimit,
  sessionFromRow,
  runFromRow,
  delegationFromRow,
  delegationValues,
  buildDelegatedPrompt,
  requiredChildSessionId,
  attemptFromRow,
  bindingFromRow,
  eventFromRow,
  artifactFromRow,
  desktopDispatchFromRow,
  desktopArtifactDeliveryFromRow,
  desktopMemoryCandidateFromRow,
  desktopAttentionOverrideFromRow,
  dispatchToQueueInput,
  deliveryToQueueInput,
  memoryCandidateToQueueInput,
  overrideToQueueInput,
  intentCandidateStatus,
  updateByColumns,
  queueRunGoalText,
  stringValue,
  numberValue,
  nullableString,
  nullableNumber,
  nullableText,
  text,
} from "./kernel-support.js";
import type {
  KernelSessionResolutionInput,
  ExecuteAgentRunInput,
  KernelRunResult,
  CancelRunResult,
  ListSessionsInput,
  KernelSessionSummary,
  GetRunInput,
  KernelRunDetails,
  InspectArtifactsInput,
  DesktopAwarenessSnapshotInput,
  DesktopAwarenessSnapshot,
  DesktopActionQueueInput,
  DesktopContextPacketPersistInput,
  ResolveDesktopDispatchInput,
  ResolveDesktopDispatchResult,
  UpdateArtifactLifecycleInput,
  UpdateArtifactLifecycleResult,
  PersistArtifactInput,
  InvalidateBindingsInput,
  InvalidateBindingsResult,
  StaleProcessLocalBindingsInput,
  StaleProcessLocalBindingsResult,
  SendAgentMessageInput,
  SpawnBackgroundAgentInput,
  SpawnBackgroundAgentResult,
  DelegateAgentInput,
  DelegateAgentResult,
  KernelEventSubscriber,
  AgentRuntimeKernelOptions,
} from "./kernel-types.js";
import { StaleAdapterBindingError } from "./kernel-types.js";

import { KernelSessions } from "./kernel-sessions.js";

export class AgentRuntimeKernel extends KernelSessions {
  private readonly desktopIntentRouter = new DesktopIntentRouter();

  buildDesktopAwarenessSnapshot(input: DesktopAwarenessSnapshotInput): DesktopAwarenessSnapshot {
    const ownerId = input.ownerId ?? "desktop-local-user";
    const limit = boundedLimit(input.limit, 50, 200);
    const sessions = this.listSessions({ ownerId, limit });
    const runs = this.store
      .allRows(
        `SELECT r.*
         FROM runs r
         JOIN sessions s ON s.session_id = r.session_id
         WHERE s.owner_id = ?
         ORDER BY r.updated_at_ms DESC
         LIMIT ?`,
        [ownerId, limit],
      )
      .map(runFromRow);
    const dispatches = this.readDesktopDispatches(ownerId, limit);
    const artifactDeliveries = this.readDesktopArtifactDeliveries(ownerId, limit);
    const memoryCandidates = this.readDesktopMemoryCandidates(ownerId, limit);
    return {
      ownerId,
      generatedAtMs: Date.now(),
      sessions,
      runs,
      dispatches,
      artifactDeliveries,
      memoryCandidates,
      actionQueue: this.listDesktopActionQueue({ ownerId, limit }),
      runtime: {
        activeExecutionCount: this.activeExecutions.size,
        registeredAdapters: this.registry.adapterIds(),
      },
    };
  }

  listDesktopActionQueue(input: DesktopActionQueueInput): DesktopActionQueueItem[] {
    const ownerId = input.ownerId ?? "desktop-local-user";
    const limit = boundedLimit(input.limit, 50, 200);
    const nowMs = Date.now();
    const runWindow = this.readDesktopQueueRuns(ownerId, Math.max(limit * 5, 200));
    const queue = buildDesktopActionQueue({
      nowMs,
      staleAfterMs: input.staleAfterMs,
      dispatches: this.readDesktopDispatches(ownerId, limit).map(dispatchToQueueInput),
      runs: runWindow,
      runItemLimit: limit,
      runSuppressionContext: runWindow,
      artifactDeliveries: this.readDesktopArtifactDeliveries(ownerId, limit).map(deliveryToQueueInput),
      candidates: [
        ...this.readDesktopMemoryCandidates(ownerId, limit).map(memoryCandidateToQueueInput),
      ],
      overrides: this.readDesktopAttentionOverrides(ownerId).map(overrideToQueueInput),
    });
    return queue.slice(0, limit);
  }

  listDesktopAttentionOverrides(ownerId: string): DesktopAttentionOverride[] {
    return this.readDesktopAttentionOverrides(ownerId);
  }

  setDesktopAttentionOverride(input: {
    ownerId: string;
    subjectKind: string;
    subjectId: string;
    dismissedAtMs?: number | null;
    hiddenUntilMs?: number | null;
    reason?: string | null;
  }): DesktopAttentionOverride {
    return this.store.upsertDesktopAttentionOverride({
      ownerId: input.ownerId,
      subjectKind: input.subjectKind,
      subjectId: input.subjectId,
      dismissedAtMs: input.dismissedAtMs ?? null,
      hiddenUntilMs: input.hiddenUntilMs ?? null,
      reason: input.reason ?? null,
    });
  }

  persistDesktopContextPacket(input: DesktopContextPacketPersistInput): BuiltDesktopContextPacket {
    const ownerId = input.ownerId ?? "desktop-local-user";
    this.validateSensitiveContextDispatches({ ...input, ownerId });
    const built = buildDesktopContextPacket({ ...input, ownerId });
    this.withTransaction(() => {
      this.store.insertDesktopContextPacket({
        ...(built.packet as unknown as NewDesktopContextPacket),
        packetJson: JSON.stringify(built.packet.packetJson),
        redactedPreviewJson: JSON.stringify(built.packet.redactedPreviewJson),
      });
      for (const accessLog of built.accessLogs) {
        this.store.insertDesktopContextAccessLog(accessLog);
      }
    });
    return built;
  }

  routeDesktopIntent(input: DesktopIntentRouteRequest & { ownerId?: string; callerSessionId?: string }): DesktopIntentRoute {
    const ownerId = input.ownerId ?? "desktop-local-user";
    const caller = this.desktopIntentCallerAuthority({
      ownerId,
      callerSessionId: input.callerSessionId,
      requestedSurfaceKind: input.surfaceKind,
    });
    const request = this.desktopIntentRequest(input, caller.surfaceKind);
    return this.desktopIntentRouter.route(request, this.desktopIntentAuthority(ownerId, caller.executionRole, request.syntaxFacts));
  }

  async applyDesktopIntentEffect<T>(
    input: {
      ownerId?: string;
      callerSessionId?: string;
      restrictiveCallerExecutionRole?: "coordinator" | "leaf";
      surfaceKind: string;
      snapshotVersion?: string;
      utterance: string;
      effect: DesktopIntentEffectKind;
      syntaxFacts?: DesktopIntentSyntaxFacts;
    },
    effect: (decision: Extract<DesktopIntentRoute, { intent: DesktopIntentEffectKind }>) => T | Promise<T>,
  ): Promise<{ decision: Extract<DesktopIntentRoute, { intent: DesktopIntentEffectKind }>; result: T }> {
    const ownerId = input.ownerId ?? "desktop-local-user";
    const caller = this.desktopIntentCallerAuthority({
      ownerId,
      callerSessionId: input.callerSessionId,
      requestedSurfaceKind: input.surfaceKind,
      restrictiveCallerExecutionRole: input.restrictiveCallerExecutionRole,
    });
    const request: DesktopIntentRouteRequest = {
      utterance: input.utterance,
      surfaceKind: caller.surfaceKind,
      snapshotVersion: input.snapshotVersion,
      syntaxFacts: input.syntaxFacts,
      proposal: { intent: input.effect },
    };
    const applied = await this.desktopIntentRouter.routeAndApply(
      request,
      this.desktopIntentAuthority(ownerId, caller.executionRole, input.syntaxFacts),
      input.effect,
      effect,
    );
    return applied as {
      decision: Extract<DesktopIntentRoute, { intent: DesktopIntentEffectKind }>;
      result: T;
    };
  }

  private desktopIntentRequest(
    input: DesktopIntentRouteRequest & { callerSessionId?: string },
    surfaceKind: string,
  ): DesktopIntentRouteRequest {
    return {
      utterance: input.utterance,
      surfaceKind,
      taskId: input.taskId,
      snapshotVersion: input.snapshotVersion,
      syntaxFacts: input.syntaxFacts,
      proposal: input.proposal,
    };
  }

  private desktopIntentCallerAuthority(input: {
    ownerId: string;
    callerSessionId?: string;
    requestedSurfaceKind: string;
    restrictiveCallerExecutionRole?: "coordinator" | "leaf";
  }): { executionRole: "coordinator" | "leaf"; surfaceKind: string } {
    let executionRole: "coordinator" | "leaf" = "coordinator";
    let surfaceKind = input.requestedSurfaceKind;
    if (input.callerSessionId) {
      const session = this.readSession(input.callerSessionId);
      this.assertSessionOwner(session, input.ownerId);
      executionRole = session.executionRole;
      surfaceKind = session.surfaceKind;
    }
    // A call-site hint can only reduce authority. It can never promote a
    // persisted leaf session into a coordinator.
    if (input.restrictiveCallerExecutionRole === "leaf") {
      executionRole = "leaf";
    }
    return { executionRole, surfaceKind };
  }

  private desktopIntentAuthority(
    ownerId: string,
    callerExecutionRole: "coordinator" | "leaf",
    syntaxFacts: DesktopIntentSyntaxFacts | undefined,
  ): DesktopIntentRouteAuthority {
    return {
      ownerId,
      callerExecutionRole,
      continuationTarget: this.desktopIntentContinuationTarget(ownerId, syntaxFacts),
      parentRunAvailable: this.desktopIntentParentRunAvailable(ownerId, syntaxFacts?.parentRunId),
      nowMs: Date.now(),
    };
  }

  private desktopIntentContinuationTarget(
    ownerId: string,
    syntaxFacts: DesktopIntentSyntaxFacts | undefined,
  ): DesktopIntentTarget | null {
    const requestedSessionId = syntaxFacts?.explicitSessionId?.trim() || null;
    const requestedRunId = syntaxFacts?.explicitRunId?.trim() || null;
    if (!requestedSessionId && !requestedRunId) return null;
    try {
      const run = requestedRunId ? this.readRun(requestedRunId) : null;
      const sessionId = requestedSessionId ?? run?.sessionId ?? null;
      if (!sessionId || (run && run.sessionId !== sessionId)) return null;
      const session = this.readSession(sessionId);
      this.assertSessionOwner(session, ownerId);
      return {
        sessionId,
        runId: run?.runId ?? null,
        status: session.status === "open" ? "open" : "closed",
      };
    } catch {
      return null;
    }
  }

  private desktopIntentParentRunAvailable(ownerId: string, parentRunId: string | null | undefined): boolean | undefined {
    const normalizedParentRunId = parentRunId?.trim();
    if (!normalizedParentRunId) return undefined;
    try {
      this.assertRunOwner(this.readRun(normalizedParentRunId), ownerId);
      return true;
    } catch {
      return false;
    }
  }

  createDesktopDispatch(input: NewDesktopCoordinatorDispatch): DesktopCoordinatorDispatch {
    return this.store.insertDesktopDispatch(input);
  }

  resolveDesktopDispatch(dispatchId: string, input: ResolveDesktopDispatchInput): ResolveDesktopDispatchResult {
    return this.withTransaction(() => {
      const dispatch = this.store.resolveDesktopDispatch(dispatchId, input);
      let grant: AgentGrant | null = null;
      if (input.status === "resolved" && input.grant && input.grant.effect === "allow") {
        const resolution = parseJsonObject(input.resolutionJson);
        if (dispatch.kind !== "approval") {
          throw new Error("Only approval dispatches can mint grants");
        }
        if (resolution.decision !== "allow") {
          throw new Error("Resolved dispatch grants require an allow resolution");
        }
        if (!dispatch.capability || input.grant.capability !== dispatch.capability) {
          throw new Error("Resolved dispatch grant capability must match the approval request");
        }
        if (!dispatch.operation || input.grant.operation !== dispatch.operation) {
          throw new Error("Resolved dispatch grant operation must match the approval request");
        }
        if (!dispatch.resourceRef || input.grant.resourcePattern !== dispatch.resourceRef) {
          throw new Error("Resolved dispatch grant resource must match the approval request");
        }
        if (!Number.isFinite(input.grant.expiresAtMs)) {
          throw new Error("Resolved dispatch grants require a finite expiry");
        }
        const sessionId = input.grant.sessionId ?? dispatch.sourceSessionId;
        if (!sessionId) {
          throw new Error("Resolved dispatch grants require a session scope");
        }
        this.assertSessionOwner(this.readSession(sessionId), input.ownerId);
        grant = this.store.insertGrant({
          ...input.grant,
          sessionId,
          runId: input.grant.runId ?? dispatch.sourceRunId,
          source: input.grant.source ?? "user",
        });
      }
      const event = dispatch.sourceSessionId
        ? this.appendEvent({
            sessionId: dispatch.sourceSessionId,
            runId: dispatch.sourceRunId,
            attemptId: dispatch.sourceAttemptId,
            type: "approval.resolved",
            payload: {
              dispatchId: dispatch.dispatchId,
              status: dispatch.status,
              resolvedBy: dispatch.resolvedBy,
              resolution: parseJsonObject(dispatch.resolutionJson),
              grantId: grant?.grantId ?? null,
            },
          })
        : null;
      return { dispatch, grant, event };
    });
  }
}
