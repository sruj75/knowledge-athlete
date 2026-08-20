import { createHash } from "node:crypto";
import { AdapterRuntimeError } from "./failures.js";
import { StaleAdapterBindingError } from "./kernel-types.js";
import type { OutboundMessage, OutboundMessageDraft } from "../protocol.js";
import type { AgentStore, RunStatus, AttemptStatus, DelegationMode, DelegationStatus, ResumeFidelity, ArtifactRole, RunMode, ArtifactLifecycleState, DesktopCandidateStatus, DesktopAttentionOverride } from "./types.js";
import type {
  AdapterBinding,
  AgentArtifact,
  AgentDelegation,
  AgentEvent,
  AgentRun,
  AgentSession,
  RunAttempt,
  DesktopCoordinatorDispatch,
  DesktopArtifactDelivery,
  DesktopMemoryCandidate,
} from "./types.js";
import type { ExecuteAgentRunInput } from "./kernel-types.js";
import type { DesktopContextSnippetInput } from "./desktop-context-packet.js";
import type { DesktopIntentSessionCandidate } from "./desktop-intent-router.js";
import type { QueueArtifactDeliveryInput, QueueCandidateInput, QueueDispatchInput, QueueOverrideInput, QueueRunInput } from "./desktop-action-queue.js";

export const ACTIVE_STATUSES: readonly RunStatus[] = ["queued", "starting", "running", "waiting_input", "waiting_approval", "cancelling"];
export const TERMINAL_STATUSES: readonly RunStatus[] = ["succeeded", "failed", "cancelled", "timed_out", "orphaned"];
export const DEFAULT_DELEGATION_MAX_DEPTH = 3;
export const HARD_DELEGATION_MAX_DEPTH = 5;
export const DEFAULT_DELEGATION_MAX_BUDGET_USD = 5;
export const HARD_DELEGATION_MAX_BUDGET_USD = 10;

export function requiresVerifiedContextDispatch(snippet: DesktopContextSnippetInput): boolean {
  const tier = snippet.sensitivityTier.toLowerCase();
  if (snippet.sourceKind === "screenshot_image") return true;
  if (snippet.sourceKind === "rewind_timeline") return true;
  if (snippet.sourceKind === "screen_current" && tier !== "low") return true;
  return tier === "sensitive";
}

export function stableHash(value: string | undefined): string {
  return createHash("sha256").update(value ?? "").digest("hex");
}

export function stableJsonStringify(value: unknown): string {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value) ?? "undefined";
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableJsonStringify(entry)).join(",")}]`;
  }
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableJsonStringify(object[key])}`)
    .join(",")}}`;
}

export function parseJsonObject(value: string | null | undefined): Record<string, unknown> {
  if (!value) return {};
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

export function bindingMetadata(input: ExecuteAgentRunInput): string {
  return JSON.stringify({
    systemPromptCacheIdentity: input.systemPromptCacheIdentity ?? null,
    dynamicContextIdentity: input.dynamicContextIdentity ?? null,
    contextPlanId: input.contextPlanId ?? null,
  });
}

export function updateByColumns<T extends Record<string, unknown>>(
  store: AgentStore,
  table: string,
  idColumn: string,
  idValue: string,
  columnMap: Record<string, string>,
  patch: Partial<T>
): void {
  const entries = Object.entries(patch).filter(([, value]) => value !== undefined);
  if (entries.length === 0) return;
  const assignments = entries.map(([key]) => `${columnMap[key] ?? key} = ?`).join(", ");
  store.execute(`UPDATE ${table} SET ${assignments} WHERE ${idColumn} = ?`, [...entries.map(([, value]) => value), idValue]);
}

export function placeholders(count: number): string {
  return Array.from({ length: count }, () => "?").join(", ");
}

export function isStaleBindingError(error: unknown): boolean {
  return error instanceof StaleAdapterBindingError || (error instanceof Error && error.name === "StaleAdapterBindingError");
}

export function queueRunGoalText(row: Record<string, unknown>): string | null {
  const input = parseJsonObject(nullableString(row.input_json));
  const prompt = input.prompt;
  return typeof prompt === "string" && prompt.trim() ? prompt : null;
}

export function messageFrom(error: unknown): string {
  if (error instanceof AdapterRuntimeError) {
    return error.failure.userMessage;
  }
  return error instanceof Error ? error.message : String(error);
}

export function text(value: unknown): string {
  return String(value);
}

export function nullableText(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

export function nullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

export function boundedLimit(value: number | undefined, fallback: number, max: number): number {
  if (value === undefined || !Number.isFinite(value)) return fallback;
  return Math.max(1, Math.min(max, Math.floor(value)));
}

export function stringValue(value: unknown): string {
  return text(value);
}

export function numberValue(value: unknown): number {
  return Number(value ?? 0);
}

export function nullableString(value: unknown): string | null {
  return nullableText(value);
}

export function desktopDispatchFromRow(row: Record<string, unknown>): DesktopCoordinatorDispatch {
  return {
    dispatchId: text(row.dispatch_id),
    ownerId: text(row.owner_id),
    kind: text(row.kind) as DesktopCoordinatorDispatch["kind"],
    priority: Number(row.priority),
    status: text(row.status) as DesktopCoordinatorDispatch["status"],
    title: text(row.title),
    decisionPrompt: text(row.decision_prompt),
    recommendedDefault: nullableText(row.recommended_default),
    sourceSessionId: nullableText(row.source_session_id),
    sourceRunId: nullableText(row.source_run_id),
    sourceAttemptId: nullableText(row.source_attempt_id),
    sourceArtifactId: nullableText(row.source_artifact_id),
    capability: nullableText(row.capability),
    operation: nullableText(row.operation),
    resourceRef: nullableText(row.resource_ref),
    payloadJson: text(row.payload_json),
    createdAtMs: Number(row.created_at_ms),
    expiresAtMs: nullableNumber(row.expires_at_ms),
    resolvedAtMs: nullableNumber(row.resolved_at_ms),
    resolvedBy: nullableText(row.resolved_by),
    resolutionJson: nullableText(row.resolution_json),
  };
}

export function desktopArtifactDeliveryFromRow(row: Record<string, unknown>): DesktopArtifactDelivery {
  return {
    deliveryId: text(row.delivery_id),
    artifactId: text(row.artifact_id),
    ownerId: text(row.owner_id),
    sourceSessionId: text(row.source_session_id),
    sourceRunId: nullableText(row.source_run_id),
    sourceAttemptId: nullableText(row.source_attempt_id),
    intendedSurface: text(row.intended_surface),
    targetKind: text(row.target_kind) as DesktopArtifactDelivery["targetKind"],
    targetRef: nullableText(row.target_ref),
    contentHash: nullableText(row.content_hash),
    reviewStatus: text(row.review_status) as DesktopArtifactDelivery["reviewStatus"],
    deliveryStatus: text(row.delivery_status) as DesktopArtifactDelivery["deliveryStatus"],
    attemptCount: Number(row.attempt_count),
    receiptJson: nullableText(row.receipt_json),
    errorJson: nullableText(row.error_json),
    createdAtMs: Number(row.created_at_ms),
    updatedAtMs: Number(row.updated_at_ms),
    deliveredAtMs: nullableNumber(row.delivered_at_ms),
  };
}

export function desktopMemoryCandidateFromRow(row: Record<string, unknown>): DesktopMemoryCandidate {
  return {
    candidateId: text(row.candidate_id),
    ownerId: text(row.owner_id),
    sourceSessionId: text(row.source_session_id),
    sourceRunId: nullableText(row.source_run_id),
    sourceArtifactId: nullableText(row.source_artifact_id),
    proposedFact: text(row.proposed_fact),
    evidenceRefsJson: text(row.evidence_refs_json),
    confidence: Number(row.confidence),
    sensitivityTier: text(row.sensitivity_tier),
    status: text(row.status) as DesktopCandidateStatus,
    createdAtMs: Number(row.created_at_ms),
    resolvedAtMs: nullableNumber(row.resolved_at_ms),
  };
}

export function desktopAttentionOverrideFromRow(row: Record<string, unknown>): DesktopAttentionOverride {
  return {
    ownerId: text(row.owner_id),
    subjectKind: text(row.subject_kind),
    subjectId: text(row.subject_id),
    hiddenUntilMs: nullableNumber(row.hidden_until_ms),
    dismissedAtMs: nullableNumber(row.dismissed_at_ms),
    reason: nullableText(row.reason),
    createdAtMs: Number(row.created_at_ms),
  };
}

export function dispatchToQueueInput(dispatch: DesktopCoordinatorDispatch): QueueDispatchInput {
  return {
    dispatchId: dispatch.dispatchId,
    ownerId: dispatch.ownerId,
    kind: dispatch.kind,
    status: dispatch.status,
    title: dispatch.title,
    priority: dispatch.priority,
    createdAtMs: dispatch.createdAtMs,
    expiresAtMs: dispatch.expiresAtMs,
    sourceSessionId: dispatch.sourceSessionId,
    sourceRunId: dispatch.sourceRunId,
  };
}

export function deliveryToQueueInput(delivery: DesktopArtifactDelivery): QueueArtifactDeliveryInput {
  return {
    deliveryId: delivery.deliveryId,
    artifactId: delivery.artifactId,
    ownerId: delivery.ownerId,
    sourceSessionId: delivery.sourceSessionId,
    sourceRunId: delivery.sourceRunId,
    deliveryStatus: delivery.deliveryStatus,
    reviewStatus: delivery.reviewStatus,
    createdAtMs: delivery.createdAtMs,
    updatedAtMs: delivery.updatedAtMs,
    targetKind: delivery.targetKind,
  };
}

export function memoryCandidateToQueueInput(candidate: DesktopMemoryCandidate): QueueCandidateInput {
  return {
    candidateId: candidate.candidateId,
    ownerId: candidate.ownerId,
    kind: "memory_candidate",
    status: candidate.status,
    createdAtMs: candidate.createdAtMs,
    sourceSessionId: candidate.sourceSessionId,
    sourceRunId: candidate.sourceRunId,
  };
}

export function overrideToQueueInput(override: DesktopAttentionOverride): QueueOverrideInput {
  return {
    ownerId: override.ownerId,
    subjectKind: override.subjectKind,
    subjectId: override.subjectId,
    hiddenUntilMs: override.hiddenUntilMs,
    dismissedAtMs: override.dismissedAtMs,
  };
}

export function intentCandidateStatus(
  status: string | null,
  runUpdatedAtMs?: number,
  nowMs?: number,
  staleAfterMs?: number,
): DesktopIntentSessionCandidate["status"] {
  if (status === "failed" || status === "timed_out") return "failed";
  if (status === "orphaned") return "orphaned";
  if (status === "cancelled") return "closed";
  // An active run that has not advanced within the stale threshold should be
  // classified as stale so the router forks instead of resuming into a hung run.
  if (
    runUpdatedAtMs !== undefined &&
    nowMs !== undefined &&
    staleAfterMs !== undefined &&
    ACTIVE_STATUSES.includes((status ?? "") as RunStatus)
  ) {
    if (nowMs - runUpdatedAtMs >= staleAfterMs) return "stale";
  }
  return "healthy";
}

export function sessionFromRow(row: Record<string, unknown>): AgentSession {
  return {
    sessionId: text(row.session_id),
    ownerId: text(row.owner_id),
    agentDefinitionId: text(row.agent_definition_id),
    title: nullableText(row.title),
    status: text(row.status) as AgentSession["status"],
    surfaceKind: text(row.surface_kind),
    executionRole: text(row.execution_role) as AgentSession["executionRole"],
    providerBoundary: text(row.provider_boundary) as AgentSession["providerBoundary"],
    externalRefKind: nullableText(row.external_ref_kind),
    externalRefId: nullableText(row.external_ref_id),
    defaultAdapterId: text(row.default_adapter_id),
    defaultCwd: nullableText(row.default_cwd),
    modelProfile: nullableText(row.model_profile),
    executionProfileGeneration: Number(row.current_profile_generation ?? 1),
    metadataJson: text(row.metadata_json),
    createdAtMs: Number(row.created_at_ms),
    updatedAtMs: Number(row.updated_at_ms),
    lastActivityAtMs: Number(row.last_activity_at_ms),
  };
}

export function runFromRow(row: Record<string, unknown>): AgentRun {
  return {
    runId: text(row.run_id),
    sessionId: text(row.session_id),
    parentRunId: nullableText(row.parent_run_id),
    clientId: text(row.client_id),
    requestId: text(row.request_id),
    idempotencyKey: nullableText(row.idempotency_key),
    status: text(row.status) as RunStatus,
    mode: text(row.mode) as RunMode,
    profileGeneration: Number(row.profile_generation ?? 1),
    inputJson: text(row.input_json),
    systemPromptHash: nullableText(row.system_prompt_hash),
    modelProfile: nullableText(row.model_profile),
    requestedModelId: nullableText(row.requested_model_id),
    cwd: nullableText(row.cwd),
    finalText: nullableText(row.final_text),
    resultJson: nullableText(row.result_json),
    errorCode: nullableText(row.error_code),
    errorMessage: nullableText(row.error_message),
    inputTokens: nullableNumber(row.input_tokens),
    outputTokens: nullableNumber(row.output_tokens),
    cacheReadTokens: nullableNumber(row.cache_read_tokens),
    cacheWriteTokens: nullableNumber(row.cache_write_tokens),
    costUsd: nullableNumber(row.cost_usd),
    createdAtMs: Number(row.created_at_ms),
    startedAtMs: nullableNumber(row.started_at_ms),
    completedAtMs: nullableNumber(row.completed_at_ms),
    updatedAtMs: Number(row.updated_at_ms),
  };
}

export function delegationFromRow(row: Record<string, unknown>): AgentDelegation {
  return {
    delegationId: text(row.delegation_id),
    parentSessionId: text(row.parent_session_id),
    parentRunId: text(row.parent_run_id),
    childSessionId: text(row.child_session_id),
    childRunId: text(row.child_run_id),
    mode: text(row.mode) as DelegationMode,
    status: text(row.status) as DelegationStatus,
    objective: text(row.objective),
    requestJson: text(row.request_json),
    resultArtifactId: nullableText(row.result_artifact_id),
    createdAtMs: Number(row.created_at_ms),
    completedAtMs: nullableNumber(row.completed_at_ms),
  };
}

export function delegationValues(delegation: AgentDelegation): unknown[] {
  return [
    delegation.delegationId,
    delegation.parentSessionId,
    delegation.parentRunId,
    delegation.childSessionId,
    delegation.childRunId,
    delegation.mode,
    delegation.status,
    delegation.objective,
    delegation.requestJson,
    delegation.resultArtifactId,
    delegation.createdAtMs,
    delegation.completedAtMs,
  ];
}

export function buildDelegatedPrompt(objective: string, context: string | undefined): string {
  const trimmedObjective = objective.trim();
  const trimmedContext = context?.trim();
  if (!trimmedContext) {
    return trimmedObjective;
  }
  return `Objective:\n${trimmedObjective}\n\nContext:\n${trimmedContext}`;
}

export function requiredChildSessionId(sessionId: string | undefined): string {
  if (!sessionId) {
    throw new Error("send_agent_message continue mode requires childSessionId");
  }
  return sessionId;
}

export function attemptFromRow(row: Record<string, unknown>): RunAttempt {
  return {
    attemptId: text(row.attempt_id),
    runId: text(row.run_id),
    attemptNo: Number(row.attempt_no),
    profileGeneration: Number(row.profile_generation ?? 1),
    status: text(row.status) as AttemptStatus,
    adapterId: text(row.adapter_id),
    adapterInstanceId: text(row.adapter_instance_id),
    runtimeNodeId: text(row.runtime_node_id),
    bindingId: nullableText(row.binding_id),
    adapterNativeRunId: nullableText(row.adapter_native_run_id),
    resumeFromAttemptId: nullableText(row.resume_from_attempt_id),
    checkpointArtifactId: nullableText(row.checkpoint_artifact_id),
    retryReason: nullableText(row.retry_reason),
    retryable: Number(row.retryable) as 0 | 1,
    cancellationRequestedAtMs: nullableNumber(row.cancellation_requested_at_ms),
    cancellationDispatchedAtMs: nullableNumber(row.cancellation_dispatched_at_ms),
    cancellationAcknowledgedAtMs: nullableNumber(row.cancellation_acknowledged_at_ms),
    startedAtMs: nullableNumber(row.started_at_ms),
    completedAtMs: nullableNumber(row.completed_at_ms),
    errorCode: nullableText(row.error_code),
    errorMessage: nullableText(row.error_message),
    metadataJson: text(row.metadata_json),
    createdAtMs: Number(row.created_at_ms),
    updatedAtMs: Number(row.updated_at_ms),
  };
}

export function bindingFromRow(row: Record<string, unknown>): AdapterBinding {
  return {
    bindingId: text(row.binding_id),
    sessionId: text(row.session_id),
    adapterId: text(row.adapter_id),
    bindingGeneration: Number(row.binding_generation),
    profileGeneration: Number(row.profile_generation ?? 1),
    adapterNativeSessionId: nullableText(row.adapter_native_session_id),
    adapterInstanceId: nullableText(row.adapter_instance_id),
    resumeFidelity: text(row.resume_fidelity) as ResumeFidelity,
    status: text(row.status) as AdapterBinding["status"],
    cwd: nullableText(row.cwd),
    modelId: nullableText(row.model_id),
    systemPromptHash: nullableText(row.system_prompt_hash),
    metadataJson: text(row.metadata_json),
    createdAtMs: Number(row.created_at_ms),
    updatedAtMs: Number(row.updated_at_ms),
    lastUsedAtMs: nullableNumber(row.last_used_at_ms),
    invalidatedAtMs: nullableNumber(row.invalidated_at_ms),
  };
}

export function eventFromRow(row: Record<string, unknown>): AgentEvent {
  return {
    eventSeq: Number(row.event_seq),
    eventId: text(row.event_id),
    sessionId: text(row.session_id),
    runId: nullableText(row.run_id),
    attemptId: nullableText(row.attempt_id),
    type: text(row.type),
    retentionClass: text(row.retention_class) as AgentEvent["retentionClass"],
    visibility: text(row.visibility) as AgentEvent["visibility"],
    payloadJson: text(row.payload_json),
    createdAtMs: Number(row.created_at_ms),
  };
}

export function artifactFromRow(row: Record<string, unknown>): AgentArtifact {
  return {
    artifactId: text(row.artifact_id),
    sessionId: text(row.session_id),
    runId: nullableText(row.run_id),
    attemptId: nullableText(row.attempt_id),
    kind: text(row.kind),
    role: text(row.role) as ArtifactRole,
    uri: text(row.uri),
    displayName: nullableText(row.display_name),
    mimeType: nullableText(row.mime_type),
    contentHash: nullableText(row.content_hash),
    sizeBytes: nullableNumber(row.size_bytes),
    lifecycleState: text(row.lifecycle_state) as ArtifactLifecycleState,
    lifecycleUpdatedAtMs: nullableNumber(row.lifecycle_updated_at_ms),
    metadataJson: text(row.metadata_json),
    createdAtMs: Number(row.created_at_ms),
  };
}

export function canonicalAdapterEventType(event: OutboundMessageDraft): string | undefined {
  switch (event.type) {
    case "text_delta":
      return "message.delta";
    case "thinking_delta":
      return "progress.updated";
    case "tool_activity":
      if (event.status === "started") return "tool.started";
      if (event.status === "completed") return "tool.completed";
      if (event.status === "failed" || event.status === "cancelled" || event.status === "interrupted") {
        return "tool.failed";
      }
      return "tool.updated";
    case "tool_use":
      return "tool.started";
    case "tool_result_display":
      return "tool.completed";
    case "error":
      return "progress.updated";
    default:
      return undefined;
  }
}

export const runColumnMap: Record<string, string> = {
  runId: "run_id",
  sessionId: "session_id",
  parentRunId: "parent_run_id",
  clientId: "client_id",
  requestId: "request_id",
  idempotencyKey: "idempotency_key",
  profileGeneration: "profile_generation",
  inputJson: "input_json",
  systemPromptHash: "system_prompt_hash",
  modelProfile: "model_profile",
  requestedModelId: "requested_model_id",
  finalText: "final_text",
  resultJson: "result_json",
  errorCode: "error_code",
  errorMessage: "error_message",
  inputTokens: "input_tokens",
  outputTokens: "output_tokens",
  cacheReadTokens: "cache_read_tokens",
  cacheWriteTokens: "cache_write_tokens",
  costUsd: "cost_usd",
  createdAtMs: "created_at_ms",
  startedAtMs: "started_at_ms",
  completedAtMs: "completed_at_ms",
  updatedAtMs: "updated_at_ms",
};

export const attemptColumnMap: Record<string, string> = {
  attemptId: "attempt_id",
  runId: "run_id",
  attemptNo: "attempt_no",
  profileGeneration: "profile_generation",
  adapterId: "adapter_id",
  adapterInstanceId: "adapter_instance_id",
  runtimeNodeId: "runtime_node_id",
  bindingId: "binding_id",
  adapterNativeRunId: "adapter_native_run_id",
  resumeFromAttemptId: "resume_from_attempt_id",
  checkpointArtifactId: "checkpoint_artifact_id",
  retryReason: "retry_reason",
  cancellationRequestedAtMs: "cancellation_requested_at_ms",
  cancellationDispatchedAtMs: "cancellation_dispatched_at_ms",
  cancellationAcknowledgedAtMs: "cancellation_acknowledged_at_ms",
  startedAtMs: "started_at_ms",
  completedAtMs: "completed_at_ms",
  errorCode: "error_code",
  errorMessage: "error_message",
  metadataJson: "metadata_json",
  createdAtMs: "created_at_ms",
  updatedAtMs: "updated_at_ms",
};

export const bindingColumnMap: Record<string, string> = {
  bindingId: "binding_id",
  sessionId: "session_id",
  adapterId: "adapter_id",
  bindingGeneration: "binding_generation",
  profileGeneration: "profile_generation",
  adapterNativeSessionId: "adapter_native_session_id",
  adapterInstanceId: "adapter_instance_id",
  resumeFidelity: "resume_fidelity",
  modelId: "model_id",
  systemPromptHash: "system_prompt_hash",
  metadataJson: "metadata_json",
  createdAtMs: "created_at_ms",
  updatedAtMs: "updated_at_ms",
  lastUsedAtMs: "last_used_at_ms",
  invalidatedAtMs: "invalidated_at_ms",
};
