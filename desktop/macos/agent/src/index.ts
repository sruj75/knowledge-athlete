/** Managed Pi desktop runtime and private Swift tool relay. */

import { createInterface } from "readline";
import packageMetadata from "../package.json" with { type: "json" };
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { createServer as createNetServer, type Socket } from "net";
import { tmpdir } from "os";
import { unlinkSync, appendFileSync } from "fs";
import type {
  InboundMessage,
  ControlToolRequestMessage,
  DirectControlToolRequestMessage,
  ExternalSurfaceRunBeginMessage,
  ExternalSurfaceToolInvokeMessage,
  ExternalSurfaceRunCompleteMessage,
  OutboundMessage,
  OutboundMessageDraft,
  QueryMessage,
  WarmupMessage,
  AuthorizedToolExecutionResultMessage,
  ResolveSurfaceSessionMessage,
  ChatCatalogListMessage,
  ChatCatalogCreateMessage,
  ChatCatalogUpdateMessage,
  ChatCatalogDeleteMessage,
  ContextSourceUpdateMessage,
  InvalidateSessionMessage,
  JournalRecordTurnMessage,
  JournalRecordExchangeMessage,
  JournalUpdateTurnMessage,
  JournalTerminalizeTurnMessage,
  JournalRepairTurnsMessage,
  JournalListTurnsMessage,
  JournalClearTurnsMessage,
  EnsureAgentSpawnJournalMessage,
  RefreshOwnerMessage,
  RevokeOwnerRuntimeMessage,
  RefreshTokenMessage,
} from "./protocol.js";
import {
  PROTOCOL_VERSION,
  RUNTIME_CAPABILITIES,
  assertPublicJournalRecordAuthority,
  assertPublicJournalUpdateAuthority,
  ensureOutboundProtocolVersion,
  isInboundResponseMessage,
  journalTerminalizationDisposition,
} from "./protocol.js";
import type { PromptBlock } from "./adapters/interface.js";
import { detectImageMimeType } from "./mime-detect.js";
import { AdapterRegistry } from "./runtime/adapter-registry.js";
import { JsonlTransport } from "./runtime/jsonl-transport.js";
import { AgentRuntimeKernel } from "./runtime/kernel.js";
import {
  adapterIdForHarnessMode,
  managedPiActivationError,
  managedPiIsActivated,
} from "./runtime/adapter-selection.js";
import {
  SWIFT_ADVERTISED_AGENT_CONTROL_TOOL_NAMES,
  handleAgentControlToolCall,
  isAgentControlToolName,
  DEFAULT_LOCAL_OWNER_ID,
  type AgentControlToolContext,
} from "./runtime/control-tools.js";
import { SqliteAgentStore } from "./runtime/sqlite-store.js";
import { OmiArtifactStorage, defaultArtifactRoot } from "./runtime/artifact-storage.js";
import { configuredPiMonoMaxWorkers } from "./runtime/worker-pool.js";
import {
  failureFromError,
  sanitizeProcessDiagnostic,
  unexpectedQueryErrorDiagnostic,
} from "./runtime/failures.js";
import { providerBoundaryForAdapter } from "./runtime/execution-policy.js";
import { executionRoleForSurface } from "./runtime/execution-policy.js";
import type { AuthorizedRunToolInvocation, RunToolExecutionLease } from "./runtime/run-tool-capability.js";
import {
  compactRealtimeSpawnToolResult,
  parseAgentSpawnProducerJournalDescriptor,
} from "./runtime/agent-spawn-journal.js";
import {
  finalizeRelayToolResult,
  finalizedToolResultOutcome,
  type RelayToolResultIdentity,
} from "./runtime/relay-tool-result.js";
import {
  clearJournalConversation,
  journalTurnForSurfaceProjection,
  journalTurnChangedWakes,
  listJournalTurns,
  recordJournalExchange,
  recordJournalTurn,
  repairOrphanedJournalTurns,
  assertPublicJournalUpdatePolicy,
  terminalizeJournalTurn,
  terminalizeJournalTurnWithReceipt,
  updateJournalTurnWithReceipt,
  updateJournalTurn,
} from "./runtime/conversation-journal.js";
import { DirectControlExecutionBroker } from "./runtime/direct-control-execution.js";
import {
  authorizeRuntimeTokenRefresh,
  establishRuntimeOwner,
  requireActiveRuntimeOwner,
  runRuntimeOwnerRevocationBarrier,
  runtimeOwnerForEffects,
} from "./runtime/runtime-owner-authority.js";
import type {
  ConversationContentBlock,
  AgentEvent,
  ConversationResource,
  ConversationTurn,
  ConversationTurnOrigin,
  ConversationTurnStatus,
} from "./runtime/types.js";
import { createStdoutLineSender } from "./stdout-line-sender.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

// --- Helpers ---

function logErr(msg: string): void {
  // Wrap to swallow EPIPE/ERR_STREAM_DESTROYED so a closed parent pipe
  // doesn't bubble out as an uncaughtException and re-enter our handlers.
  try {
    process.stderr.write(`[agent] ${msg}\n`);
  } catch {
    // ignore — parent pipe is gone; we'll exit shortly anyway
  }
}

// Queue stdout lines so a full parent pipe waits on `drain` instead of
// blocking the event loop inside kernel subscribers / query completion.
const writeStdoutLine = createStdoutLineSender(
  (chunk) => process.stdout.write(chunk),
  (listener) => {
    process.stdout.once("drain", listener);
  },
  (err) => {
    logErr(`Failed to write to stdout: ${err}`);
  }
);

function send(msg: OutboundMessageDraft): void {
  writeStdoutLine(JSON.stringify(ensureOutboundProtocolVersion(msg)) + "\n");
}

function runtimeErrorEnvelope(error: unknown): { message: string; failure: ReturnType<typeof failureFromError> } {
  const message = sanitizeProcessDiagnostic(error instanceof Error ? error.message : String(error))
    || "Runtime request rejected";
  const failure = {
    code: "runtime_error",
    source: "runtime" as const,
    retryable: false,
    userMessage: message,
  };
  return { message: failure.userMessage, failure };
}

type ChatCatalogRequest =
  | ChatCatalogListMessage
  | ChatCatalogCreateMessage
  | ChatCatalogUpdateMessage
  | ChatCatalogDeleteMessage;

function requireCatalogCorrelation(request: ChatCatalogRequest): void {
  if (!request.requestId?.trim() || !request.clientId?.trim()) {
    throw new Error("chat_catalog_requires_correlation");
  }
}

function sendCatalogError(request: ChatCatalogRequest, error: unknown): void {
  const envelope = runtimeErrorEnvelope(error);
  send({
    type: "error",
    protocolVersion: request.protocolVersion,
    requestId: request.requestId,
    clientId: request.clientId,
    message: envelope.message,
    failure: envelope.failure,
  });
}

function agentStateDir(): string {
  const stateDir = process.env.HEYINTENTIVE_AGENT_STATE_DIR?.trim();
  if (!stateDir) {
    throw new Error("Agent runtime requires HEYINTENTIVE_AGENT_STATE_DIR");
  }
  return stateDir;
}

function agentArtifactsDir(): string {
  return defaultArtifactRoot(process.env);
}

// --- OMI tools relay via Unix socket ---

let omiToolsPipePath = "";
let omiToolsClients: Socket[] = [];
let agentControlToolContext: AgentControlToolContext | undefined;
let runtimeKernel: AgentRuntimeKernel | undefined;
let currentOwnerId = DEFAULT_LOCAL_OWNER_ID;
let ownerAuthorityEstablished = false;
interface OwnerRuntimeRevocationReceipt {
  ownerId: string;
  revokedRunIds: string[];
  invalidatedBindingIds: string[];
}
let lastOwnerRuntimeRevocation: OwnerRuntimeRevocationReceipt | null = null;
const establishedOwnerId = () => runtimeOwnerForEffects({
  ownerId: currentOwnerId,
  established: ownerAuthorityEstablished,
});
const directControlExecutions = new DirectControlExecutionBroker({
  activeOwnerId: establishedOwnerId,
});
const capabilityRejectionCounts = new Map<string, number>();

function resolveActiveOwner(requestedOwnerId: string | undefined): string {
  return requireActiveRuntimeOwner(
    { ownerId: currentOwnerId, established: ownerAuthorityEstablished },
    requestedOwnerId,
  );
}

function journalOrigin(raw: unknown): ConversationTurnOrigin {
  switch (raw) {
    case "typed_chat":
    case "floating_chat":
    case "realtime_voice":
    case "agent_runtime":
    case "notification":
    case "tool_runtime":
    case "swift_backfill":
    case "legacy":
      return raw;
    case "proactive_notification":
      return "notification";
    case "floating_spawn":
      return "agent_runtime";
    case "floating_provider_unavailable":
    case "floating_invalid_brief":
      return "floating_chat";
    default:
      throw new Error("Unknown journal turn origin");
  }
}

// Pending Swift execution is keyed only by the canonical run capability tuple.
const pendingToolCalls = new Map<
  string,
  {
    client: Socket;
    callId: string;
    invocation: AuthorizedRunToolInvocation;
    timeout: ReturnType<typeof setTimeout>;
  }
>();

const pendingExternalToolCalls = new Map<
  string,
  {
    request: ExternalSurfaceToolInvokeMessage;
    invocation: AuthorizedRunToolInvocation;
    timeout: ReturnType<typeof setTimeout>;
  }
>();

const TERMINAL_RUN_TOOL_EVENTS = new Set([
  "run.succeeded",
  "run.failed",
  "run.cancelled",
  "run.timed_out",
  "run.orphaned",
  "attempt.succeeded",
  "attempt.failed",
  "attempt.cancelled",
  "attempt.timed_out",
  "attempt.orphaned",
]);

function toolCallPendingKey(input: {
  invocationId: string;
}): string {
  return input.invocationId;
}

function relayResultIdentity(
  callId: string,
  invocation?: AuthorizedRunToolInvocation,
): RelayToolResultIdentity {
  if (invocation) {
    return {
      invocationId: invocation.invocationId,
      ownerId: invocation.ownerId,
      sessionId: invocation.sessionId,
      runId: invocation.runId,
      attemptId: invocation.attemptId,
      toolName: invocation.canonicalToolName,
    };
  }
  // Capability rejection occurs before a kernel-owned invocation exists. It
  // still receives a canonical envelope, but cannot claim a fabricated run.
  return {
    invocationId: `relay:${callId}`,
    ownerId: currentOwnerId,
    sessionId: "unknown",
    runId: "unknown",
    attemptId: "unknown",
    toolName: "unknown_relay_tool",
  };
}

function finalizeRelayResult(
  callId: string,
  result: string,
  invocation?: AuthorizedRunToolInvocation,
  outcome?: "succeeded" | "failed",
): string {
  return finalizeRelayToolResult({
    identity: relayResultIdentity(callId, invocation),
    result,
    outcome,
    kernel: runtimeKernel,
    artifactRoot: agentArtifactsDir(),
  });
}

/** Resolve a pending tool call with a result from Swift */
function resolveToolCall(msg: AuthorizedToolExecutionResultMessage): void {
  const key = toolCallPendingKey(msg);
  const pending = pendingToolCalls.get(key);
  if (pending) {
    try {
      const result = finalizeRelayResult(pending.callId, msg.result, pending.invocation, msg.outcome);
      const finalizedOutcome = controlToolInvocationOutcome(result);
      runtimeKernel?.completeRunToolInvocation({
        invocationId: msg.invocationId,
        ownerId: msg.ownerId,
        sessionId: msg.sessionId,
        runId: msg.runId,
        attemptId: msg.attemptId,
        profileGeneration: msg.profileGeneration,
        manifestVersion: msg.manifestVersion,
        manifestDigest: msg.manifestDigest,
        daemonBootEpoch: msg.daemonBootEpoch,
        executionGeneration: msg.executionGeneration,
        inputHash: msg.inputHash,
        capabilityRef: pending.invocation.capabilityRef,
        activeOwnerId: currentOwnerId,
        outcome: finalizedOutcome,
        result,
      });
      pendingToolCalls.delete(key);
      clearTimeout(pending.timeout);
      writeFinalizedRelayToolResult(pending.client, pending.callId, result);
    } catch (error) {
      logErr(`Rejected authorized tool execution result invocation=${msg.invocationId}: ${error}`);
    }
    return;
  }
  const external = pendingExternalToolCalls.get(key);
  if (external) {
    try {
      const result = finalizeRelayResult(external.request.requestId, msg.result, external.invocation, msg.outcome);
      const finalizedOutcome = controlToolInvocationOutcome(result);
      runtimeKernel?.completeRunToolInvocation({
        invocationId: msg.invocationId,
        ownerId: msg.ownerId,
        sessionId: msg.sessionId,
        runId: msg.runId,
        attemptId: msg.attemptId,
        profileGeneration: msg.profileGeneration,
        manifestVersion: msg.manifestVersion,
        manifestDigest: msg.manifestDigest,
        daemonBootEpoch: msg.daemonBootEpoch,
        executionGeneration: msg.executionGeneration,
        inputHash: msg.inputHash,
        capabilityRef: external.invocation.capabilityRef,
        activeOwnerId: currentOwnerId,
        outcome: finalizedOutcome,
        result,
      });
      pendingExternalToolCalls.delete(key);
      clearTimeout(external.timeout);
      send({
        type: "external_surface_tool_result",
        requestId: external.request.requestId,
        clientId: external.request.clientId,
        ownerId: external.invocation.ownerId,
        sessionId: external.invocation.sessionId,
        runId: external.invocation.runId,
        attemptId: external.invocation.attemptId,
        invocationId: external.invocation.invocationId,
        // This acknowledges the correlated protocol request. The model-facing
        // tool outcome remains in the canonical `result` envelope; Swift
        // requires this transport acknowledgement to read that typed failure.
        ok: true,
        result,
      });
    } catch (error) {
      logErr(`Rejected external authorized tool result invocation=${msg.invocationId}: ${error}`);
    }
    return;
  }
  logErr(`Warning: no pending tool invocation for invocation=${msg.invocationId}`);
}

function externalAuthorityError(error: unknown, fallbackCode: string): { code: string; message: string } {
  const rawCode = error && typeof error === "object" && "code" in error
    ? String((error as { code: unknown }).code)
    : fallbackCode;
  const code = /^[a-z0-9_]{1,64}$/.test(rawCode) ? rawCode : fallbackCode;
  return {
    code,
    message: error instanceof Error ? error.message : "External surface authority rejected the request",
  };
}

function registerPendingExternalToolCall(
  request: ExternalSurfaceToolInvokeMessage,
  invocation: AuthorizedRunToolInvocation,
): { request: ExternalSurfaceToolInvokeMessage; invocation: AuthorizedRunToolInvocation; timeout: ReturnType<typeof setTimeout> } {
  const key = toolCallPendingKey(invocation);
  if (pendingExternalToolCalls.has(key) || pendingToolCalls.has(key)) {
    throw Object.assign(new Error("Duplicate tool invocation"), { code: "invocation_replayed" });
  }
  const pending = {
    request,
    invocation,
    timeout: setTimeout(() => {
      const active = pendingExternalToolCalls.get(key);
      if (!active) return;
      pendingExternalToolCalls.delete(key);
      try {
        runtimeKernel?.markRunToolInvocationOutcomeUnknown(active.invocation, "swift_tool_timeout");
      } catch (error) {
        logErr(`Failed to mark external invocation outcome unknown: ${error}`);
      }
      send({
        type: "external_surface_tool_result",
        requestId: active.request.requestId,
        clientId: active.request.clientId,
        ownerId: active.invocation.ownerId,
        sessionId: active.invocation.sessionId,
        runId: active.invocation.runId,
        attemptId: active.invocation.attemptId,
        invocationId: active.invocation.invocationId,
        ok: false,
        error: { code: "swift_tool_timeout", message: "Timed out waiting for the authorized tool executor" },
      });
    }, 120_000),
  };
  pendingExternalToolCalls.set(key, pending);
  return pending;
}

function cancelPendingExternalToolCallsForAttempt(input: {
  ownerId: string;
  runId: string;
  attemptId: string;
  errorCode: string;
}): void {
  for (const [key, pending] of pendingExternalToolCalls) {
    if (
      pending.invocation.ownerId !== input.ownerId
      || pending.invocation.runId !== input.runId
      || pending.invocation.attemptId !== input.attemptId
    ) continue;
    pendingExternalToolCalls.delete(key);
    clearTimeout(pending.timeout);
    try {
      runtimeKernel?.markRunToolInvocationOutcomeUnknown(pending.invocation, input.errorCode);
    } catch (error) {
      logErr(`Failed to terminalize external invocation: ${error}`);
    }
    send({
      type: "external_surface_tool_result",
      requestId: pending.request.requestId,
      clientId: pending.request.clientId,
      ownerId: pending.invocation.ownerId,
      sessionId: pending.invocation.sessionId,
      runId: pending.invocation.runId,
      attemptId: pending.invocation.attemptId,
      invocationId: pending.invocation.invocationId,
      ok: false,
      error: { code: input.errorCode, message: "External surface run terminated during tool execution" },
    });
  }
}

function rejectPendingToolCallsForOwner(
  ownerId: string,
  errorCode = "owner_changed",
  message = "Active owner changed during tool execution",
): void {
  for (const [key, pending] of pendingToolCalls) {
    if (pending.invocation.ownerId !== ownerId) continue;
    pendingToolCalls.delete(key);
    clearTimeout(pending.timeout);
    writeRelayToolResult(
      pending.client,
      pending.callId,
      relayError(errorCode, message),
      pending.invocation,
      "failed",
    );
  }
  for (const [key, pending] of pendingExternalToolCalls) {
    if (pending.invocation.ownerId !== ownerId) continue;
    pendingExternalToolCalls.delete(key);
    clearTimeout(pending.timeout);
    send({
      type: "external_surface_tool_result",
      requestId: pending.request.requestId,
      clientId: pending.request.clientId,
      ownerId: pending.invocation.ownerId,
      sessionId: pending.invocation.sessionId,
      runId: pending.invocation.runId,
      attemptId: pending.invocation.attemptId,
      invocationId: pending.invocation.invocationId,
      ok: false,
      error: { code: errorCode, message },
    });
  }
}

/** The broker terminalizes the ledger before subscribers see terminal events. */
function rejectPendingToolCallsForKernelEvent(event: AgentEvent): void {
  if (!TERMINAL_RUN_TOOL_EVENTS.has(event.type)) return;
  const matches = (invocation: AuthorizedRunToolInvocation): boolean =>
    !!event.runId
    && invocation.runId === event.runId
    && (!event.attemptId || invocation.attemptId === event.attemptId);
  const errorCode = event.type.startsWith("attempt.") ? "attempt_terminal" : "run_terminal";
  for (const [key, pending] of pendingToolCalls) {
    if (!matches(pending.invocation)) continue;
    pendingToolCalls.delete(key);
    clearTimeout(pending.timeout);
    writeRelayToolResult(
      pending.client,
      pending.callId,
      relayError(errorCode, "Run tool authority ended before Swift returned a result"),
      pending.invocation,
      "failed",
    );
  }
  for (const [key, pending] of pendingExternalToolCalls) {
    if (!matches(pending.invocation)) continue;
    pendingExternalToolCalls.delete(key);
    clearTimeout(pending.timeout);
    send({
      type: "external_surface_tool_result",
      requestId: pending.request.requestId,
      clientId: pending.request.clientId,
      ownerId: pending.invocation.ownerId,
      sessionId: pending.invocation.sessionId,
      runId: pending.invocation.runId,
      attemptId: pending.invocation.attemptId,
      invocationId: pending.invocation.invocationId,
      ok: false,
      error: { code: errorCode, message: "Run tool authority ended before Swift returned a result" },
    });
  }
}

function resolveClientToolCalls(client: Socket, result: string): void {
  for (const [key, pending] of pendingToolCalls) {
    if (pending.client !== client) continue;
    pendingToolCalls.delete(key);
    clearTimeout(pending.timeout);
    try {
      runtimeKernel?.markRunToolInvocationOutcomeUnknown(pending.invocation, "relay_client_disconnected");
    } catch (error) {
      logErr(`Failed to mark disconnected tool invocation outcome unknown: ${error}`);
    }
    writeRelayToolResult(client, pending.callId, result, pending.invocation, "failed");
  }
}

function relayError(code: string, message: string): string {
  return JSON.stringify({ ok: false, error: { code, message } });
}

function controlToolInvocationOutcome(result: string): "succeeded" | "failed" {
  return finalizedToolResultOutcome(result);
}

function writeRelayToolResult(
  client: Socket,
  callId: string,
  result: string,
  invocation?: AuthorizedRunToolInvocation,
  outcome?: "succeeded" | "failed",
): string {
  const finalized = finalizeRelayResult(callId, result, invocation, outcome);
  writeFinalizedRelayToolResult(client, callId, finalized);
  return finalized;
}

function writeFinalizedRelayToolResult(client: Socket, callId: string, result: string): void {
  try {
    client.write(JSON.stringify({ type: "tool_result", callId, result }) + "\n");
  } catch (error) {
    logErr(`Failed to write relay tool result: ${error}`);
  }
}

/** Start the private Unix socket server used by the owned Pi extension. */
function startOmiToolsRelay(): Promise<string> {
  const pipePath = join(tmpdir(), `intentive-tools-${process.pid}.sock`);

  // Clean up any stale socket
  try {
    unlinkSync(pipePath);
  } catch {
    // ignore
  }

  return new Promise((resolve, reject) => {
    const server = createNetServer((client: Socket) => {
      omiToolsClients.push(client);
      let buffer = "";

      client.on("data", (data: Buffer) => {
        buffer += data.toString();
        let newlineIdx;
        while ((newlineIdx = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, newlineIdx);
          buffer = buffer.slice(newlineIdx + 1);
          if (!line.trim()) continue;

          try {
            const msg = JSON.parse(line) as {
              type: string;
              callId: string;
              invocationId?: string;
              name: string;
              input: Record<string, unknown>;
              capabilityRef?: string;
            };

            if (msg.type === "tool_use") {
              const capabilityRef = msg.capabilityRef?.trim();
              const invocationId = msg.invocationId?.trim() || msg.callId?.trim();
              if (!runtimeKernel || !capabilityRef || !invocationId) {
                writeRelayToolResult(
                  client,
                  msg.callId,
                  relayError("missing_run_capability", "Tool relay requires an active run capability"),
                );
                continue;
              }
              let authorized;
              let routedProposal;
              try {
                routedProposal = runtimeKernel.routeRelayedRunToolProposal({
                  capabilityRef,
                  toolName: msg.name,
                  toolInput: msg.input ?? {},
                  activeOwnerId: currentOwnerId,
                });
                authorized = runtimeKernel.authorizeRelayedRunToolInvocation({
                  capabilityRef,
                  invocationId,
                  toolName: routedProposal.toolName,
                  toolInput: routedProposal.toolInput,
                  activeOwnerId: currentOwnerId,
                });
              } catch (error) {
                const code = error && typeof error === "object" && "code" in error
                  ? String((error as { code: unknown }).code)
                  : "capability_rejected";
                writeRelayToolResult(
                  client,
                  msg.callId,
                  relayError(code, error instanceof Error ? error.message : "Tool capability rejected"),
                );
                continue;
              }

              if (isAgentControlToolName(authorized.canonicalToolName)) {
                void (async () => {
                  let result: string;
                  let outcome: "succeeded" | "failed" = "succeeded";
                  let executionLease: RunToolExecutionLease | undefined;
                  try {
                    runtimeKernel?.markRunToolInvocationDispatched(authorized);
                    executionLease = runtimeKernel?.acquireRunToolExecutionLease(
                      authorized,
                      establishedOwnerId,
                    );
                    if (!agentControlToolContext) {
                      throw new Error("Agent runtime kernel is not ready");
                    }
                    const activeSession = requireControlSessionPolicy(
                      authorized.sessionId,
                      authorized.ownerId,
                    );
                    const preparedSpawn = authorized.canonicalToolName === "spawn_agent"
                      ? runtimeKernel?.prepareAuthorizedSpawnAgentControlInvocation({
                          ownerId: authorized.ownerId,
                          sessionId: authorized.sessionId,
                          runId: authorized.runId,
                          attemptId: authorized.attemptId,
                          invocationId: authorized.invocationId,
                          surfaceKind: authorized.surfaceKind,
                          toolInput: routedProposal.toolInput,
                        })
                      : undefined;
                    result = await handleAgentControlToolCall(
                      {
                        ...agentControlToolContext,
                        callerSessionId: authorized.sessionId,
                        executionRole: activeSession.executionRole,
                        providerBoundary: activeSession.providerBoundary,
                        defaultAdapterId: activeSession.defaultAdapterId,
                        authorizedProducerJournal: preparedSpawn?.producerJournal,
                        authorizedCallerRunId: preparedSpawn?.parentRunId,
                        authorizedToolInvocation: {
                          invocationId: authorized.invocationId,
                          runId: authorized.runId,
                          attemptId: authorized.attemptId,
                          toolName: authorized.canonicalToolName,
                        },
                        getOwnerId: establishedOwnerId,
                        executionLease,
                      },
                      authorized.canonicalToolName,
                      preparedSpawn?.toolInput ?? routedProposal.toolInput,
                    );
                    outcome = controlToolInvocationOutcome(result);
                  } catch (error) {
                    outcome = "failed";
                    const authorityError = externalAuthorityError(error, "control_tool_failed");
                    result = relayError(
                      error instanceof Error && error.message === "Agent runtime kernel is not ready"
                        ? "runtime_not_ready"
                        : authorityError.code,
                      authorityError.message,
                    );
                  }
                  executionLease?.release();
                  const finalizedResult = finalizeRelayResult(msg.callId, result, authorized, outcome);
                  const finalizedOutcome = controlToolInvocationOutcome(finalizedResult);
                  try {
                    runtimeKernel?.completeRunToolInvocation({
                      invocationId: authorized.invocationId,
                      ownerId: authorized.ownerId,
                      sessionId: authorized.sessionId,
                      runId: authorized.runId,
                      attemptId: authorized.attemptId,
                      profileGeneration: authorized.profileGeneration,
                      manifestVersion: authorized.manifestVersion,
                      manifestDigest: authorized.manifestDigest,
                      daemonBootEpoch: authorized.daemonBootEpoch,
                      executionGeneration: authorized.executionGeneration,
                      inputHash: authorized.inputHash,
                      capabilityRef: authorized.capabilityRef,
                      activeOwnerId: currentOwnerId,
                      outcome: finalizedOutcome,
                      result: finalizedResult,
                    });
                  } catch (error) {
                    logErr(`Failed to complete runtime control invocation ${authorized.invocationId}: ${error}`);
                  }
                  writeFinalizedRelayToolResult(client, msg.callId, finalizedResult);
                })();
                continue;
              }

              const callId = msg.callId;
              const pendingKey = toolCallPendingKey({
                invocationId,
              });
              if (pendingToolCalls.has(pendingKey)) {
                writeRelayToolResult(
                  client,
                  callId,
                  relayError("invocation_replayed", "Duplicate tool invocation"),
                  authorized,
                  "failed",
                );
                continue;
              }

              const timeout = setTimeout(() => {
                const pending = pendingToolCalls.get(pendingKey);
                if (!pending) return;
                pendingToolCalls.delete(pendingKey);
                try {
                  runtimeKernel?.markRunToolInvocationOutcomeUnknown(pending.invocation, "swift_tool_timeout");
                } catch (error) {
                  logErr(`Failed to mark timed-out tool invocation outcome unknown: ${error}`);
                }
                writeRelayToolResult(
                  pending.client,
                  pending.callId,
                  relayError("swift_tool_timeout", "Timed out waiting for the Swift tool executor"),
                  pending.invocation,
                  "failed",
                );
              }, 120_000);
              pendingToolCalls.set(pendingKey, {
                client,
                callId,
                invocation: authorized,
                timeout,
              });
              runtimeKernel.markRunToolInvocationDispatched(authorized);
              send({
                type: "authorized_tool_execution",
                invocationId,
                ownerId: authorized.ownerId,
                sessionId: authorized.sessionId,
                runId: authorized.runId,
                attemptId: authorized.attemptId,
                profileGeneration: authorized.profileGeneration,
                manifestVersion: authorized.manifestVersion,
                manifestDigest: authorized.manifestDigest,
                daemonBootEpoch: authorized.daemonBootEpoch,
                executionGeneration: authorized.executionGeneration,
                toolName: authorized.canonicalToolName,
                input: routedProposal.toolInput,
                inputHash: authorized.inputHash,
                effectClass: authorized.effectClass,
                retryPolicy: authorized.retryPolicy,
                surfaceKind: authorized.surfaceKind,
                externalRefKind: authorized.externalRefKind,
                externalRefId: authorized.externalRefId,
                originatingUserText: authorized.originatingUserText,
                precedingAssistantText: authorized.precedingAssistantText,
                runMode: authorized.runMode,
                chatMode: authorized.chatMode,
              });
            }
          } catch {
            logErr(`Failed to parse intentive-tools message: ${line.slice(0, 200)}`);
          }
        }
      });

      client.on("close", () => {
        omiToolsClients = omiToolsClients.filter((c) => c !== client);
        resolveClientToolCalls(client, "Error: intentive-tools relay client disconnected");
      });

      client.on("error", (err) => {
        logErr(`intentive-tools client error: ${err.message}`);
        resolveClientToolCalls(client, "Error: intentive-tools relay client error");
      });
    });

    server.listen(pipePath, () => {
      logErr(`intentive-tools relay socket: ${pipePath}`);
      resolve(pipePath);
    });

    server.on("error", reject);

    // Clean up on exit
    process.on("exit", () => {
      server.close();
      try {
        unlinkSync(pipePath);
      } catch {
        // ignore
      }
    });
  });
}

function requireControlSessionPolicy(sessionId: string | undefined, ownerId: string | undefined) {
  if (!sessionId || !ownerId || !agentControlToolContext) {
    throw new Error("missing active control session policy");
  }
  return agentControlToolContext.kernel.executionPolicyForOwnedSession(sessionId, ownerId);
}

// --- Error handling ---

/**
 * Write to /tmp/agent-crash.log as fallback when stderr might be lost.
 * Hard-capped at CRASH_LOG_MAX_LINES per process to prevent runaway disk
 * fill (we shipped a build that wrote 100s of GBs into this file in a tight
 * EPIPE re-entry loop).
 */
const CRASH_LOG_MAX_LINES = 100;
let crashLogLineCount = 0;
function logCrash(msg: string): void {
  if (crashLogLineCount >= CRASH_LOG_MAX_LINES) return;
  crashLogLineCount += 1;
  try {
    const ts = new Date().toISOString();
    appendFileSync("/tmp/agent-crash.log", `[${ts}] ${msg}\n`);
  } catch {
    // ignore
  }
}

// Once we've decided to bail because the parent pipe is gone, suppress all
// further error handling so logErr/logCrash don't keep re-entering on
// every subsequent failed write while the runtime tears down.
let shuttingDown = false;
function bailOnBrokenPipe(reason: string): void {
  if (shuttingDown) return;
  shuttingDown = true;
  logErr(reason);
  logCrash(reason);
  process.exit(0);
}

process.on("unhandledRejection", (reason) => {
  if (shuttingDown) return;
  const code = (reason as NodeJS.ErrnoException | undefined)?.code;
  if (code === "EPIPE" || code === "ERR_STREAM_DESTROYED") {
    bailOnBrokenPipe(`Unhandled rejection (${code}, pipe closed)`);
    return;
  }
  logErr(`Unhandled rejection: ${reason}`);
  logCrash(`Unhandled rejection: ${reason}`);
});

process.on("uncaughtException", (err) => {
  if (shuttingDown) return;
  const code = (err as NodeJS.ErrnoException).code;
  if (code === "EPIPE" || code === "ERR_STREAM_DESTROYED") {
    // Parent has gone away; staying alive without a pipe just produces
    // more EPIPEs. Exit cleanly instead of returning (the previous
    // `return` left the process running and looping on every retry).
    bailOnBrokenPipe(`Caught ${code} in uncaughtException (pipe closed)`);
    return;
  }
  logErr(`Uncaught exception: ${err.message}\n${err.stack ?? ""}`);
  logCrash(`Uncaught exception: ${err.message}\n${err.stack ?? ""}`);
  try {
    const envelope = runtimeErrorEnvelope(err);
    send({ type: "error", message: envelope.message, failure: envelope.failure });
  } catch {
    // already broken
  }
  process.exit(1);
});

process.stdout.on("error", (err) => {
  if ((err as NodeJS.ErrnoException).code === "EPIPE") {
    bailOnBrokenPipe("stdout EPIPE — parent disconnected");
    return;
  }
  logErr(`stdout error: ${err.message}`);
  logCrash(`stdout error: ${err.message}`);
});

process.stderr.on("error", (err) => {
  // If stderr is also gone, we have nothing to write to. Bail silently.
  const code = (err as NodeJS.ErrnoException).code;
  if (code === "EPIPE" || code === "ERR_STREAM_DESTROYED") {
    if (!shuttingDown) {
      shuttingDown = true;
      logCrash("stderr EPIPE — parent disconnected");
      process.exit(0);
    }
  }
});

// --- Main ---

async function main(): Promise<void> {
  logErr(`Bridge main() starting (pid=${process.pid}, node=${process.version}, execPath=${process.execPath})`);

  const defaultHarnessMode = process.env.HARNESS_MODE || "piMono";
  const defaultAdapterId = adapterIdForHarnessMode(defaultHarnessMode);
  logErr(`Default harness mode: ${defaultHarnessMode}`);

  // 1. Start Unix socket for the Intentive tools relay
  omiToolsPipePath = await startOmiToolsRelay();
  logErr("intentive-tools relay started");
  process.env.OMI_BRIDGE_PIPE = omiToolsPipePath;

  const store = new SqliteAgentStore({
    stateDir: agentStateDir(),
    canonicalExecutionProfile: {
      adapterId: "pi-mono",
      modelProfile: "gemini-3.7-flash",
      workingDirectory: agentArtifactsDir(),
    },
  });
  const registry = new AdapterRegistry();
  const artifactStorage = new OmiArtifactStorage({ rootDir: agentArtifactsDir() });
  logErr(`Intentive artifact root: ${artifactStorage.rootDir}`);
  const kernel = new AgentRuntimeKernel({
    store,
    registry,
    artifactStorage,
    onToolCapabilityRejected: (code) => {
      const count = (capabilityRejectionCounts.get(code) ?? 0) + 1;
      capabilityRejectionCounts.set(code, count);
      logErr(`run_tool_capability_rejected code=${code} count=${count}`);
    },
  });
  kernel.subscribe(rejectPendingToolCallsForKernelEvent);
  runtimeKernel = kernel;
  let piMonoClasses: typeof import("./adapters/pi-mono.js") | undefined;
  let piMonoAuthToken = process.env.OMI_AUTH_TOKEN;
  const piMonoAdapters = new Set<import("./adapters/pi-mono.js").PiMonoAdapter>();
  const ensurePiMonoAdapter = async (authToken: string | undefined): Promise<boolean> => {
    if (!managedPiIsActivated(authToken)) return false;
    piMonoAuthToken = authToken;
    piMonoClasses ??= await import("./adapters/pi-mono.js");
    if (!registry.has("pi-mono")) {
      registry.register("pi-mono", () => {
        const harness = new piMonoClasses!.PiMonoAdapter({
          omiApiBaseUrl: process.env.OMI_API_BASE_URL,
          authToken: piMonoAuthToken,
        });
        piMonoAdapters.add(harness);
        return new piMonoClasses!.PiMonoRuntimeAdapter(harness);
      }, configuredPiMonoMaxWorkers());
      logErr(`Pi-mono adapter registered (maxWorkers=${configuredPiMonoMaxWorkers()})`);
    }
    return true;
  };

  const piMonoAvailable = await ensurePiMonoAdapter(process.env.OMI_AUTH_TOKEN);
  if (!piMonoAvailable && process.env.OMI_AGENT_ALLOW_CONTROL_ONLY !== "1") {
    const msg = managedPiActivationError();
    logErr(msg);
    send({ type: "error", message: msg });
    process.exit(1);
  } else if (!piMonoAvailable) {
    logErr("Managed Pi unavailable; starting the test-only control runtime");
  }
  agentControlToolContext = {
    kernel,
    defaultAdapterId,
    workingDirectory: agentArtifactsDir(),
    providerBoundary: providerBoundaryForAdapter(defaultAdapterId),
    executionRole: "coordinator",
    getOwnerId: establishedOwnerId,
  };
  const transport = new JsonlTransport({
    kernel,
    send,
    log: logErr,
    defaultAdapterId,
    activeOwnerId: establishedOwnerId,
  });
  const revokeOwnerRuntimeWork = (
    ownerId: string,
    reason: "owner_changed" | "owner_state_cleared",
  ): { errors: unknown[]; revokedRunIds: string[] } => {
    const errors: unknown[] = [];
    let revokedRunIds: string[] = [];
    const attempt = (work: () => void): void => {
      try {
        work();
      } catch (error) {
        errors.push(error);
      }
    };
    attempt(() => { directControlExecutions.abortOwner(ownerId, reason); });
    attempt(() => { revokedRunIds = transport.revokeOwner(ownerId, reason); });
    attempt(() => { kernel.revokeRunToolCapabilitiesForOwner(ownerId, "owner_changed"); });
    attempt(() => {
      rejectPendingToolCallsForOwner(
        ownerId,
        reason,
        reason === "owner_changed"
          ? "Active owner changed during tool execution"
          : "Owner runtime state was cleared during tool execution",
      );
    });
    return { errors, revokedRunIds };
  };
  const throwOwnerRevocationErrors = (errors: readonly unknown[]): void => {
    if (errors.length === 0) return;
    const first = errors[0];
    throw new Error(
      `Owner runtime revocation failed at ${errors.length} boundary(s): ${first instanceof Error ? first.message : String(first)}`,
      { cause: first },
    );
  };
  const terminalizeAndClearOwnerRuntime = (
    ownerId: string,
    reason: "owner_changed" | "owner_state_cleared",
  ): OwnerRuntimeRevocationReceipt => {
    lastOwnerRuntimeRevocation = null;
    const revocation = revokeOwnerRuntimeWork(ownerId, reason);
    let result: ReturnType<AgentRuntimeKernel["clearOwnerState"]> | undefined;
    try {
      result = kernel.clearOwnerState(ownerId);
    } catch (error) {
      revocation.errors.push(error);
    }
    throwOwnerRevocationErrors(revocation.errors);
    const receipt = {
      ownerId,
      revokedRunIds: revocation.revokedRunIds,
      invalidatedBindingIds: result!.invalidatedBindingIds,
    };
    lastOwnerRuntimeRevocation = receipt;
    return receipt;
  };
  const resolveJournalSurface = (input: {
    ownerId: string;
    surfaceKind: string;
    externalRefKind: string;
    externalRefId: string;
  }) => {
    const resolver = input.externalRefKind === "chat" && input.externalRefId !== "default"
      ? kernel.resolveExistingSurfaceSession.bind(kernel)
      : kernel.resolveSurfaceSession.bind(kernel);
    return resolver({
      ownerId: input.ownerId,
      surfaceRef: {
        surfaceKind: input.surfaceKind,
        externalRefKind: input.externalRefKind,
        externalRefId: input.externalRefId,
      },
      defaultAdapterId,
      providerBoundary: "managed_cloud",
      modelProfile: "gemini-3.7-flash",
      defaultCwd: agentArtifactsDir(),
      executionRole: executionRoleForSurface(input),
    });
  };
  const journalTurnProjection = (turn: ConversationTurn) => ({ ...turn });
  // 3. Signal readiness
  send({
    type: "init",
    sessionId: "",
    agentControlTools: SWIFT_ADVERTISED_AGENT_CONTROL_TOOL_NAMES,
    runtimeVersion: packageMetadata.version,
    runtimeCapabilities: [...RUNTIME_CAPABILITIES],
    runtimeAdapterIds: registry.adapterIds(),
  });
  logErr("Agent runtime bridge started, waiting for queries...");

  // 4. Read JSON lines from Swift
  const rl = createInterface({ input: process.stdin, terminal: false });

  rl.on("line", async (line: string) => {
    if (!line.trim()) return;

    let msg: InboundMessage;
    try {
      msg = JSON.parse(line) as InboundMessage;
    } catch {
      logErr(`Invalid JSON: ${line}`);
      return;
    }

    try {
      switch (msg.type) {
      case "query":
        (async () => {
          const query = msg as QueryMessage;
          if (!query.clientId?.trim()) {
            throw new Error("query requires clientId");
          }
          if (!query.requestId?.trim()) {
            throw new Error("query requires requestId");
          }
          const queryOwnerId = resolveActiveOwner(query.ownerId);
          query.ownerId = queryOwnerId;
          query.requestId = query.requestId.trim();
          if (!(await ensurePiMonoAdapter(process.env.OMI_AUTH_TOKEN))) {
            throw new Error(managedPiActivationError());
          }
          await transport.handleQuery(query);
        })().catch((err) => {
          const diagnostic = unexpectedQueryErrorDiagnostic(err);
          if (diagnostic) logErr(diagnostic);
          const query = msg as QueryMessage;
          const envelope = runtimeErrorEnvelope(err);
          send({
            type: "error",
            message: envelope.message,
            failure: envelope.failure,
            protocolVersion: PROTOCOL_VERSION,
            requestId: query.requestId,
            clientId: query.clientId,
          });
        });
        break;

      case "warmup": {
        const wm = msg as WarmupMessage;
        wm.ownerId = resolveActiveOwner(wm.ownerId);
        transport.handleWarmup(wm);
        break;
      }

      case "resolve_surface_session": {
        const resolve = msg as ResolveSurfaceSessionMessage;
        const ownerId = resolveActiveOwner(resolve.ownerId);
        const existing = store.getOptionalRow(
          `SELECT agent_session_id FROM surface_conversations
           WHERE owner_id = ? AND surface_kind = ? AND external_ref_kind = ? AND external_ref_id = ?`,
          [ownerId, resolve.surfaceKind, resolve.externalRefKind, resolve.externalRefId],
        );
        const resolved = kernel.resolveSurfaceSession({
          ownerId,
          surfaceRef: {
            surfaceKind: resolve.surfaceKind,
            externalRefKind: resolve.externalRefKind,
            externalRefId: resolve.externalRefId,
          },
          defaultAdapterId,
          providerBoundary: "managed_cloud",
          modelProfile: "gemini-3.7-flash",
          defaultCwd: agentArtifactsDir(),
          executionRole: executionRoleForSurface(resolve),
          title: resolve.title ?? null,
        });
        const profile = kernel.sessionExecutionProfile(resolved.agentSessionId, ownerId);
        send({
          type: "surface_session_resolved",
          protocolVersion: resolve.protocolVersion,
          requestId: resolve.requestId,
          clientId: resolve.clientId,
          created: !existing,
          conversationId: resolved.conversationId,
          sessionId: resolved.agentSessionId,
          profile: {
            profileGeneration: profile.generation,
            adapterId: profile.adapterId,
            credentialScope: profile.credentialScope,
            modelProfile: profile.modelProfile,
            workingDirectory: profile.workingDirectory,
            executionRole: profile.executionRole,
          },
        });
        break;
      }

      case "chat_catalog_list": {
        const request = msg as ChatCatalogListMessage;
        try {
          requireCatalogCorrelation(request);
          const ownerId = resolveActiveOwner(request.ownerId);
          send({
            type: "chat_catalog_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            ownerId,
            operation: "list",
            chats: kernel.listChatCatalog({ ownerId }),
            retainedAttachmentUris: kernel.retainedAttachmentUris(ownerId),
          });
        } catch (error) {
          sendCatalogError(request, error);
        }
        break;
      }

      case "chat_catalog_create": {
        const request = msg as ChatCatalogCreateMessage;
        try {
          requireCatalogCorrelation(request);
          const ownerId = resolveActiveOwner(request.ownerId);
          send({
            type: "chat_catalog_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            ownerId,
            operation: "create",
            chat: kernel.createChatCatalog({
              ownerId,
              chatId: request.chatId,
              title: request.title,
              defaultAdapterId,
              modelProfile: "gemini-3.7-flash",
              defaultCwd: agentArtifactsDir(),
            }),
          });
        } catch (error) {
          sendCatalogError(request, error);
        }
        break;
      }

      case "chat_catalog_update": {
        const request = msg as ChatCatalogUpdateMessage;
        try {
          requireCatalogCorrelation(request);
          const ownerId = resolveActiveOwner(request.ownerId);
          send({
            type: "chat_catalog_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            ownerId,
            operation: "update",
            chat: kernel.updateChatCatalog({
              ownerId,
              chatId: request.chatId,
              title: request.title,
              titleOrigin: request.titleOrigin,
              expectedTitleOrigin: request.expectedTitleOrigin,
              starred: request.starred,
            }),
          });
        } catch (error) {
          sendCatalogError(request, error);
        }
        break;
      }

      case "chat_catalog_delete": {
        const request = msg as ChatCatalogDeleteMessage;
        try {
          requireCatalogCorrelation(request);
          const ownerId = resolveActiveOwner(request.ownerId);
          const receipt = kernel.deleteChatCatalog({ ownerId, chatId: request.chatId });
          send({
            type: "chat_catalog_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            ownerId,
            operation: "delete",
            deletedChatId: receipt.deletedChatId,
            retainedAttachmentUris: receipt.retainedAttachmentUris,
          });
        } catch (error) {
          sendCatalogError(request, error);
        }
        break;
      }

      case "context_source_update": {
        const update = msg as ContextSourceUpdateMessage;
        const ownerId = resolveActiveOwner(update.ownerId);
        const result = kernel.updateContextSource({
          ownerId,
          sessionId: update.sessionId,
          surfaceKind: update.surfaceKind,
          source: update.source,
          sourceRevision: update.sourceRevision,
          outcome: update.outcome,
          capturedAtMs: update.capturedAtMs,
          expiresAtMs: update.expiresAtMs,
          payload: update.payload,
        });
        send({
          type: "context_source_updated",
          protocolVersion: update.protocolVersion,
          requestId: update.requestId,
          clientId: update.clientId,
          sessionId: update.sessionId,
          source: update.source,
          sourceRevision: update.sourceRevision,
          changed: result.changed,
          snapshotVersion: result.snapshot.version,
          snapshotGeneration: result.snapshot.snapshotGeneration,
          rendererFingerprint: result.snapshot.rendererFingerprint,
          capabilityVersion: result.snapshot.capabilityVersion,
        });
        break;
      }

      case "get_context_snapshot": {
        const ownerId = resolveActiveOwner(msg.ownerId);
        send({
          type: "context_snapshot",
          protocolVersion: msg.protocolVersion,
          requestId: msg.requestId,
          clientId: msg.clientId,
          snapshot: kernel.contextSnapshot(msg.sessionId, ownerId, msg.surfaceKind),
        });
        break;
      }

      case "authorized_tool_execution_result":
        resolveToolCall(msg);
        break;

      case "external_surface_run_begin": {
        const request = msg as ExternalSurfaceRunBeginMessage;
        const requestId = request.requestId?.trim();
        const clientId = request.clientId?.trim();
        try {
          if (!requestId || !clientId) throw new Error("External surface begin requires requestId and clientId");
          const ownerId = resolveActiveOwner(request.ownerId);
          const result = kernel.beginExternalSurfaceRun({
            ownerId,
            sessionId: request.sessionId,
            turnId: request.turnId,
            prompt: request.prompt,
            mode: request.mode,
            clientId,
            requestId,
          });
          send({
            type: "external_surface_run_begin_result",
            requestId,
            clientId,
            ownerId,
            sessionId: result.sessionId,
            turnId: result.turnId,
            ok: true,
            runId: result.runId,
            attemptId: result.attemptId,
            duplicate: result.duplicate,
          });
        } catch (error) {
          send({
            type: "external_surface_run_begin_result",
            requestId,
            clientId,
            ownerId: request.ownerId ?? "",
            sessionId: request.sessionId ?? "",
            turnId: request.turnId ?? "",
            ok: false,
            error: externalAuthorityError(error, "external_run_begin_rejected"),
          });
        }
        break;
      }

      case "external_surface_tool_invoke": {
        const request = msg as ExternalSurfaceToolInvokeMessage;
        const requestId = request.requestId?.trim();
        const clientId = request.clientId?.trim();
        try {
          if (!requestId || !clientId) throw new Error("External tool invocation requires requestId and clientId");
          const ownerId = resolveActiveOwner(request.ownerId);
          if (!request.input || typeof request.input !== "object" || Array.isArray(request.input)) {
            throw new Error("External tool invocation input must be an object");
          }
          const routed = kernel.routeExternalSurfaceToolInvocation({
            ownerId,
            sessionId: request.sessionId,
            runId: request.runId,
            attemptId: request.attemptId,
            invocationId: request.invocationId,
            toolName: request.toolName,
            toolInput: request.input,
          });
          const authorized = kernel.authorizeExternalSurfaceToolInvocation({
            ownerId,
            sessionId: request.sessionId,
            runId: request.runId,
            attemptId: request.attemptId,
            invocationId: request.invocationId,
            toolName: routed.toolName,
            toolInput: routed.toolInput,
            activeOwnerId: currentOwnerId,
          });
          if (isAgentControlToolName(authorized.canonicalToolName)) {
            kernel.markRunToolInvocationDispatched(authorized);
            const spawnDescriptor = routed.toolName === "spawn_agent"
              ? parseAgentSpawnProducerJournalDescriptor(
                  ((routed.toolInput.metadata as Record<string, unknown> | undefined) ?? {}).producerJournal,
                )
              : undefined;
            let result: string;
            let outcome: "succeeded" | "failed" = "succeeded";
            let executionLease: RunToolExecutionLease | undefined;
            try {
              executionLease = kernel.acquireRunToolExecutionLease(authorized, establishedOwnerId);
              if (!agentControlToolContext) throw new Error("Agent runtime kernel is not ready");
              const activeSession = requireControlSessionPolicy(authorized.sessionId, authorized.ownerId);
              result = await handleAgentControlToolCall(
                {
                  ...agentControlToolContext,
                  callerSessionId: authorized.sessionId,
                  executionRole: activeSession.executionRole,
                  providerBoundary: activeSession.providerBoundary,
                  defaultAdapterId: activeSession.defaultAdapterId,
                  authorizedProducerJournal: spawnDescriptor,
                  authorizedCallerRunId: routed.toolName === "spawn_agent" ? request.runId : undefined,
                  authorizedToolInvocation: {
                    invocationId: authorized.invocationId,
                    runId: authorized.runId,
                    attemptId: authorized.attemptId,
                    toolName: authorized.canonicalToolName,
                  },
                  getOwnerId: establishedOwnerId,
                  executionLease,
                },
                authorized.canonicalToolName,
                routed.toolInput,
              );
              outcome = controlToolInvocationOutcome(result);
            } catch (error) {
              outcome = "failed";
              const authorityError = externalAuthorityError(error, "control_tool_failed");
              result = relayError(
                authorityError.code,
                authorityError.message,
              );
            }
            executionLease?.release();
            if (outcome === "succeeded" && spawnDescriptor) {
              result = compactRealtimeSpawnToolResult(result, spawnDescriptor);
              // A parent journal acknowledgement without a durable child
              // receipt is an external-spawn failure, not a successful tool
              // invocation. Keep the control ledger aligned with the exact
              // compact semantic result we return to Swift/provider.
              outcome = controlToolInvocationOutcome(result);
            }
            const finalizedResult = finalizeRelayResult(requestId, result, authorized, outcome);
            const finalizedOutcome = controlToolInvocationOutcome(finalizedResult);
            kernel.completeRunToolInvocation({
              invocationId: authorized.invocationId,
              ownerId: authorized.ownerId,
              sessionId: authorized.sessionId,
              runId: authorized.runId,
              attemptId: authorized.attemptId,
              profileGeneration: authorized.profileGeneration,
              manifestVersion: authorized.manifestVersion,
              manifestDigest: authorized.manifestDigest,
              daemonBootEpoch: authorized.daemonBootEpoch,
              executionGeneration: authorized.executionGeneration,
              inputHash: authorized.inputHash,
              capabilityRef: authorized.capabilityRef,
              activeOwnerId: currentOwnerId,
              outcome: finalizedOutcome,
              result: finalizedResult,
            });
            send({
              type: "external_surface_tool_result",
              requestId,
              clientId,
              ownerId: authorized.ownerId,
              sessionId: authorized.sessionId,
              runId: authorized.runId,
              attemptId: authorized.attemptId,
              invocationId: authorized.invocationId,
              // `ok` means the correlated external protocol request was
              // processed. A failed tool result is carried in its canonical
              // envelope so Swift can return it to the provider unchanged.
              ok: true,
              result: finalizedResult,
            });
            break;
          }

          kernel.markRunToolInvocationDispatched(authorized);
          registerPendingExternalToolCall(request, authorized);
          send({
            type: "authorized_tool_execution",
            invocationId: authorized.invocationId,
            ownerId: authorized.ownerId,
            sessionId: authorized.sessionId,
            runId: authorized.runId,
            attemptId: authorized.attemptId,
            profileGeneration: authorized.profileGeneration,
            manifestVersion: authorized.manifestVersion,
            manifestDigest: authorized.manifestDigest,
            daemonBootEpoch: authorized.daemonBootEpoch,
            executionGeneration: authorized.executionGeneration,
            toolName: authorized.canonicalToolName,
            input: routed.toolInput,
            inputHash: authorized.inputHash,
            effectClass: authorized.effectClass,
            retryPolicy: authorized.retryPolicy,
            surfaceKind: authorized.surfaceKind,
            externalRefKind: authorized.externalRefKind,
            externalRefId: authorized.externalRefId,
            originatingUserText: authorized.originatingUserText,
            precedingAssistantText: authorized.precedingAssistantText,
            runMode: authorized.runMode,
            chatMode: authorized.chatMode,
            ...(routed.recoveredFromDelegation
              ? { policyRecovery: "permission_delegation_to_native" as const }
              : {}),
          });
        } catch (error) {
          send({
            type: "external_surface_tool_result",
            requestId,
            clientId,
            ownerId: request.ownerId ?? "",
            sessionId: request.sessionId ?? "",
            runId: request.runId ?? "",
            attemptId: request.attemptId ?? "",
            invocationId: request.invocationId ?? "",
            ok: false,
            error: externalAuthorityError(error, "external_tool_rejected"),
          });
        }
        break;
      }

      case "external_surface_run_complete": {
        const request = msg as ExternalSurfaceRunCompleteMessage;
        const requestId = request.requestId?.trim();
        const clientId = request.clientId?.trim();
        try {
          if (!requestId || !clientId) throw new Error("External surface completion requires requestId and clientId");
          const ownerId = resolveActiveOwner(request.ownerId);
          if (request.terminalStatus === "failed" || request.terminalStatus === "cancelled") {
            cancelPendingExternalToolCallsForAttempt({
              ownerId,
              runId: request.runId,
              attemptId: request.attemptId,
              errorCode: "external_run_terminal",
            });
          }
          const result = kernel.completeExternalSurfaceRun({
            ownerId,
            sessionId: request.sessionId,
            runId: request.runId,
            attemptId: request.attemptId,
            terminalStatus: request.terminalStatus,
            errorCode: request.errorCode,
          });
          send({
            type: "external_surface_run_complete_result",
            requestId,
            clientId,
            ownerId,
            sessionId: result.sessionId,
            runId: result.runId,
            attemptId: result.attemptId,
            ok: true,
            terminalStatus: result.terminalStatus,
            duplicate: result.duplicate,
          });
        } catch (error) {
          send({
            type: "external_surface_run_complete_result",
            requestId,
            clientId,
            ownerId: request.ownerId ?? "",
            sessionId: request.sessionId ?? "",
            runId: request.runId ?? "",
            attemptId: request.attemptId ?? "",
            ok: false,
            error: externalAuthorityError(error, "external_run_complete_rejected"),
          });
        }
        break;
      }

      case "journal_record_turn": {
        const request = msg as JournalRecordTurnMessage;
        const ownerId = resolveActiveOwner(request.ownerId);
        const resolved = resolveJournalSurface({
          ownerId,
          surfaceKind: request.surfaceKind,
          externalRefKind: request.externalRefKind,
          externalRefId: request.externalRefId,
        });
        const turn = request.turn ?? {};
        assertPublicJournalRecordAuthority(turn);
        const result = recordJournalTurn(store, {
          ownerId,
          conversationId: resolved.conversationId,
          turnId: typeof turn.turnId === "string" ? turn.turnId : undefined,
          producerId: typeof turn.producerId === "string" ? turn.producerId : undefined,
          role: turn.role === "assistant" ? "assistant" : "user",
          surfaceKind: request.surfaceKind,
          origin: journalOrigin(turn.origin ?? "typed_chat"),
          status: (typeof turn.status === "string" ? turn.status : "pending") as ConversationTurnStatus,
          content: typeof turn.content === "string" ? turn.content : "",
          contentBlocks: Array.isArray(turn.contentBlocks)
            ? turn.contentBlocks as ConversationContentBlock[]
            : [],
          resources: Array.isArray(turn.resources) ? turn.resources as ConversationResource[] : [],
          metadataJson: typeof turn.metadataJson === "string" ? turn.metadataJson : "{}",
          createdAtMs: typeof turn.createdAtMs === "number" ? turn.createdAtMs : undefined,
        });
        const range = listJournalTurns(store, {
          ownerId,
          conversationId: resolved.conversationId,
          afterTurnSeq: Math.max(0, result.turn.turnSeq - 1),
          limit: 1,
        });
        send({
          type: "journal_operation_result",
          protocolVersion: request.protocolVersion,
          requestId: request.requestId,
          clientId: request.clientId,
          operation: "record",
          conversationId: resolved.conversationId,
          surfaceKind: request.surfaceKind,
          externalRefKind: request.externalRefKind,
          externalRefId: request.externalRefId,
          turn: journalTurnProjection(result.turn),
          turns: [],
          clearedCount: 0,
          highWaterTurnSeq: range.highWaterTurnSeq,
          generationBaseTurnSeq: range.generationBaseTurnSeq,
          conversationGeneration: range.generation,
        });
        if (result.created) {
          send({
            type: "journal_turn_changed",
            ownerId,
            conversationGeneration: range.generation,
            generationBaseTurnSeq: range.generationBaseTurnSeq,
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
            turn: journalTurnProjection(result.turn),
          });
        }
        break;
      }

      case "journal_record_exchange": {
        const request = msg as JournalRecordExchangeMessage;
        try {
          const ownerId = resolveActiveOwner(request.ownerId);
          const resolved = resolveJournalSurface({
            ownerId,
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
          });
          const turns = Array.isArray(request.turns) ? request.turns : [];
          turns.forEach(assertPublicJournalRecordAuthority);
          const result = recordJournalExchange(store, {
            ownerId,
            conversationId: resolved.conversationId,
            turns: turns.map((turn) => ({
              turnId: typeof turn.turnId === "string" ? turn.turnId : undefined,
              producerId: typeof turn.producerId === "string" ? turn.producerId : undefined,
              role: turn.role === "assistant" ? "assistant" as const : "user" as const,
              surfaceKind: request.surfaceKind,
              origin: journalOrigin(turn.origin ?? "typed_chat"),
              status: (typeof turn.status === "string" ? turn.status : "pending") as ConversationTurnStatus,
              content: typeof turn.content === "string" ? turn.content : "",
              contentBlocks: Array.isArray(turn.contentBlocks)
                ? turn.contentBlocks as ConversationContentBlock[]
                : [],
              resources: Array.isArray(turn.resources) ? turn.resources as ConversationResource[] : [],
              metadataJson: typeof turn.metadataJson === "string" ? turn.metadataJson : "{}",
              createdAtMs: typeof turn.createdAtMs === "number" ? turn.createdAtMs : undefined,
            })),
          });
          const range = listJournalTurns(store, {
            ownerId,
            conversationId: resolved.conversationId,
            afterTurnSeq: 0,
            limit: 1,
          });
          send({
            type: "journal_operation_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            operation: "record_exchange",
            conversationId: resolved.conversationId,
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
            turns: result.turns.map(journalTurnProjection),
            clearedCount: 0,
            highWaterTurnSeq: range.highWaterTurnSeq,
            generationBaseTurnSeq: range.generationBaseTurnSeq,
            conversationGeneration: range.generation,
            firstCompletedRealPair: result.firstCompletedRealPair,
            firstCompletedRealExchange: result.firstCompletedRealExchange ?? undefined,
          });
          // recordJournalExchange has returned, so its outer transaction is
          // committed before any observer can see either half.
          for (const turn of result.createdTurns) {
            send({
              type: "journal_turn_changed",
              ownerId,
              conversationGeneration: range.generation,
              generationBaseTurnSeq: range.generationBaseTurnSeq,
              surfaceKind: request.surfaceKind,
              externalRefKind: request.externalRefKind,
              externalRefId: request.externalRefId,
              turn: journalTurnProjection(turn),
            });
          }
        } catch (error) {
          const envelope = runtimeErrorEnvelope(error);
          send({
            type: "error",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            message: envelope.message,
            failure: envelope.failure,
          });
        }
        break;
      }

      case "journal_update_turn": {
        const request = msg as JournalUpdateTurnMessage;
        try {
          const ownerId = resolveActiveOwner(request.ownerId);
          const resolved = resolveJournalSurface({
            ownerId,
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
          });
          const update = request.update ?? {};
          assertPublicJournalUpdateAuthority(update);
          const turnId = typeof update.turnId === "string" ? update.turnId : "";
          const before = store.getRow(
            `SELECT turn_seq, producing_run_id
             FROM conversation_turns WHERE conversation_id = ? AND turn_id = ?`,
            [resolved.conversationId, turnId],
          );
          if (
            before.producing_run_id != null
            && (update.status === "completed" || update.status === "failed")
          ) {
            throw new Error("Runtime-produced journal turns require kernel-authoritative terminalization");
          }
          const parsedUpdate = {
            ownerId,
            conversationId: resolved.conversationId,
            turnId,
            status: typeof update.status === "string" ? update.status as ConversationTurnStatus : undefined,
            content: typeof update.content === "string" ? update.content : undefined,
            replaceContentBlocks: Array.isArray(update.replaceContentBlocks)
              ? update.replaceContentBlocks as ConversationContentBlock[]
              : undefined,
            appendContentBlocks: Array.isArray(update.appendContentBlocks)
              ? update.appendContentBlocks as ConversationContentBlock[]
              : undefined,
            replaceResources: Array.isArray(update.replaceResources)
              ? update.replaceResources as ConversationResource[]
              : undefined,
            appendResources: Array.isArray(update.appendResources)
              ? update.appendResources as ConversationResource[]
              : undefined,
            metadataJson: typeof update.metadataJson === "string" ? update.metadataJson : undefined,
          };
          assertPublicJournalUpdatePolicy(store, parsedUpdate);
          const updated = updateJournalTurnWithReceipt(store, parsedUpdate);
          const turn = updated.turn;
          const range = listJournalTurns(store, {
            ownerId,
            conversationId: resolved.conversationId,
            afterTurnSeq: Math.max(0, turn.turnSeq - 1),
            limit: 1,
          });
          send({
            type: "journal_operation_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            operation: "update",
            conversationId: resolved.conversationId,
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
            turn: journalTurnProjection(turn),
            turns: [],
            clearedCount: 0,
            highWaterTurnSeq: range.highWaterTurnSeq,
            generationBaseTurnSeq: range.generationBaseTurnSeq,
            conversationGeneration: range.generation,
            firstCompletedRealPair: updated.firstCompletedRealPair,
            firstCompletedRealExchange: updated.firstCompletedRealExchange ?? undefined,
          });
          if (turn.turnSeq !== Number(before.turn_seq)) {
            send({
              type: "journal_turn_changed",
              ownerId,
              conversationGeneration: range.generation,
              generationBaseTurnSeq: range.generationBaseTurnSeq,
              surfaceKind: request.surfaceKind,
              externalRefKind: request.externalRefKind,
              externalRefId: request.externalRefId,
              turn: journalTurnProjection(turn),
            });
          }
        } catch (error) {
          const envelope = runtimeErrorEnvelope(error);
          send({
            type: "error",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            message: envelope.message,
            failure: envelope.failure,
          });
        }
        break;
      }

      case "journal_terminalize_turn": {
        const request = msg as JournalTerminalizeTurnMessage;
        try {
          const ownerId = resolveActiveOwner(request.ownerId);
          const resolved = resolveJournalSurface({
            ownerId,
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
          });
          const terminalization = request.terminalization;
          const disposition = journalTerminalizationDisposition(terminalization);
          const turnId = typeof terminalization?.turnId === "string" ? terminalization.turnId : "";
          const before = store.getRow(
            "SELECT turn_seq FROM conversation_turns WHERE conversation_id = ? AND turn_id = ?",
            [resolved.conversationId, turnId],
          );
          const terminalized = terminalizeJournalTurnWithReceipt(store, {
            ownerId,
            conversationId: resolved.conversationId,
            turnId,
            producingRunId: typeof terminalization?.producingRunId === "string"
              ? terminalization.producingRunId
              : "",
            producingAttemptId: typeof terminalization?.producingAttemptId === "string"
              ? terminalization.producingAttemptId
              : "",
            disposition,
            content: typeof terminalization?.content === "string" ? terminalization.content : undefined,
            replaceContentBlocks: Array.isArray(terminalization?.replaceContentBlocks)
              ? terminalization.replaceContentBlocks as ConversationContentBlock[]
              : undefined,
            replaceResources: Array.isArray(terminalization?.replaceResources)
              ? terminalization.replaceResources as ConversationResource[]
              : undefined,
          });
          const turn = terminalized.turn;
          const range = listJournalTurns(store, {
            ownerId,
            conversationId: resolved.conversationId,
            afterTurnSeq: Math.max(0, turn.turnSeq - 1),
            limit: 1,
          });
          send({
            type: "journal_operation_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            operation: "update",
            conversationId: resolved.conversationId,
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
            turn: journalTurnProjection(turn),
            turns: [],
            clearedCount: 0,
            highWaterTurnSeq: range.highWaterTurnSeq,
            generationBaseTurnSeq: range.generationBaseTurnSeq,
            conversationGeneration: range.generation,
            firstCompletedRealPair: terminalized.firstCompletedRealPair,
            firstCompletedRealExchange: terminalized.firstCompletedRealExchange ?? undefined,
          });
          if (turn.turnSeq !== Number(before.turn_seq)) {
            send({
              type: "journal_turn_changed",
              ownerId,
              conversationGeneration: range.generation,
              generationBaseTurnSeq: range.generationBaseTurnSeq,
              surfaceKind: request.surfaceKind,
              externalRefKind: request.externalRefKind,
              externalRefId: request.externalRefId,
              turn: journalTurnProjection(turn),
            });
          }
        } catch (error) {
          const envelope = runtimeErrorEnvelope(error);
          send({
            type: "error",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            message: envelope.message,
            failure: envelope.failure,
          });
        }
        break;
      }

      case "journal_repair_turns": {
        const request = msg as JournalRepairTurnsMessage;
        try {
          const ownerId = resolveActiveOwner(request.ownerId);
          const turns = repairOrphanedJournalTurns(store, {
            ownerId,
            turnIds: Array.isArray(request.turnIds)
              ? request.turnIds.filter((turnId): turnId is string => typeof turnId === "string")
              : [],
          });
          send({
            type: "journal_operation_result",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            operation: "repair",
            conversationId: turns[0]?.conversationId ?? "",
            surfaceKind: request.surfaceKind,
            externalRefKind: request.externalRefKind,
            externalRefId: request.externalRefId,
            turns: turns.map(journalTurnProjection),
            clearedCount: 0,
            highWaterTurnSeq: 0,
            generationBaseTurnSeq: 0,
            conversationGeneration: 1,
          });
          for (const turn of turns) {
            for (const wake of journalTurnChangedWakes(store, ownerId, turn)) {
              send({
                type: "journal_turn_changed",
                ...wake,
              });
            }
          }
        } catch (error) {
          const envelope = runtimeErrorEnvelope(error);
          send({
            type: "error",
            protocolVersion: request.protocolVersion,
            requestId: request.requestId,
            clientId: request.clientId,
            message: envelope.message,
            failure: envelope.failure,
          });
        }
        break;
      }

      case "journal_list_turns": {
        const request = msg as JournalListTurnsMessage;
        const ownerId = resolveActiveOwner(request.ownerId);
        const resolved = resolveJournalSurface({
          ownerId,
          surfaceKind: request.surfaceKind,
          externalRefKind: request.externalRefKind,
          externalRefId: request.externalRefId,
        });
        const range = listJournalTurns(store, {
          ownerId,
          conversationId: resolved.conversationId,
          afterTurnSeq: request.afterTurnSeq,
          limit: request.limit,
        });
        send({
          type: "journal_operation_result",
          protocolVersion: request.protocolVersion,
          requestId: request.requestId,
          clientId: request.clientId,
          operation: "list",
          conversationId: resolved.conversationId,
          surfaceKind: request.surfaceKind,
          externalRefKind: request.externalRefKind,
          externalRefId: request.externalRefId,
          turns: range.turns.map((turn) => journalTurnProjection(
            journalTurnForSurfaceProjection(turn, request.surfaceKind),
          )),
          clearedCount: 0,
          highWaterTurnSeq: range.highWaterTurnSeq,
          generationBaseTurnSeq: range.generationBaseTurnSeq,
          conversationGeneration: range.generation,
        });
        break;
      }

      case "journal_clear_turns": {
        const request = msg as JournalClearTurnsMessage;
        const ownerId = resolveActiveOwner(request.ownerId);
        const resolved = resolveJournalSurface({
          ownerId,
          surfaceKind: request.surfaceKind,
          externalRefKind: request.externalRefKind,
          externalRefId: request.externalRefId,
        });
        const result = clearJournalConversation(store, {
          ownerId,
          conversationId: resolved.conversationId,
          expectedGeneration: request.expectedGeneration,
        });
        send({
          type: "journal_operation_result",
          protocolVersion: request.protocolVersion,
          requestId: request.requestId,
          clientId: request.clientId,
          operation: "clear",
          conversationId: resolved.conversationId,
          surfaceKind: request.surfaceKind,
          externalRefKind: request.externalRefKind,
          externalRefId: request.externalRefId,
          turns: [],
          clearedCount: result.deletedTurns,
          highWaterTurnSeq: result.highWaterTurnSeq,
          generationBaseTurnSeq: result.generationBaseTurnSeq,
          conversationGeneration: result.generation,
        });
        break;
      }

      case "ensure_agent_spawn_journal": {
        const request = msg as EnsureAgentSpawnJournalMessage;
        const ownerId = resolveActiveOwner(request.ownerId);
        const result = kernel.ensureAgentSpawnJournal({
          ownerId,
          sessionId: request.sessionId,
          runId: request.runId,
        });
        send({
          type: "agent_spawn_journal_ensured",
          protocolVersion: request.protocolVersion,
          requestId: request.requestId,
          clientId: request.clientId,
          ownerId,
          sessionId: result.sessionId,
          runId: result.runId,
          conversationId: result.conversationId,
          userTurn: result.userTurn ? journalTurnProjection(result.userTurn) : null,
          assistantTurn: journalTurnProjection(result.assistantTurn),
        });
        for (const turn of [result.userTurn, result.assistantTurn]) {
          if (!turn) continue;
          for (const wake of journalTurnChangedWakes(store, ownerId, turn)) {
            send({ type: "journal_turn_changed", ...wake, turn: journalTurnProjection(wake.turn) });
          }
        }
        break;
      }

      case "control_tool": {
        const control = msg as ControlToolRequestMessage;
        send({
          type: "control_tool_result",
          protocolVersion: control.protocolVersion,
          requestId: control.requestId?.trim(),
          clientId: control.clientId,
          name: control.name,
          result: relayError(
            "legacy_control_tool_removed",
            "Agent-originated control tools require a registered run capability",
          ),
        });
        break;
      }

      case "direct_control_tool": {
        const control = msg as DirectControlToolRequestMessage;
        const requestId = control.requestId?.trim();
        const clientId = control.clientId?.trim();
        const ownerGuard = control.ownerId?.trim() ?? "";
        if (!requestId || !clientId) {
          send({
            type: "control_tool_result",
            protocolVersion: PROTOCOL_VERSION,
            requestId,
            clientId,
            ownerId: ownerGuard,
            name: control.name,
            result: relayError("invalid_request", "Direct control requires tracing requestId and clientId"),
          });
          break;
        }
        const execution = agentControlToolContext
          ? await directControlExecutions.execute({
              ownerId: ownerGuard,
              clientId,
              requestId,
              name: control.name,
              input: control.input ?? {},
            }, agentControlToolContext)
          : {
              ownerId: ownerGuard,
              name: control.name,
              result: relayError("runtime_not_ready", "Agent runtime kernel is not ready"),
            };
        send({
          type: "control_tool_result",
          protocolVersion: control.protocolVersion,
          requestId,
          clientId,
          ownerId: execution.ownerId,
          name: execution.name,
          result: execution.result,
        });
        break;
      }

      case "interrupt":
        logErr("Interrupt requested by user");
        transport.handleInterrupt({ ...msg, ownerId: resolveActiveOwner(msg.ownerId) }).catch((err) => {
          logErr(`Interrupt error: ${err}`);
        });
        break;

      case "revoke_owner_runtime": {
        const request = msg as RevokeOwnerRuntimeMessage;
        const requestId = request.requestId?.trim();
        const clientId = request.clientId?.trim();
        const requestedOwnerId = request.ownerId?.trim() ?? "";
        try {
          if (!requestId || !clientId) {
            throw new Error("Owner runtime revocation requires requestId and clientId");
          }
          const barrier = runRuntimeOwnerRevocationBarrier({
            state: { ownerId: currentOwnerId, established: ownerAuthorityEstablished },
            requestedOwnerId,
            inertOwnerId: DEFAULT_LOCAL_OWNER_ID,
            lastReceipt: lastOwnerRuntimeRevocation,
            // Authority is made inert before any abort/terminalization boundary.
            // No new A or B work can be admitted while the correlated barrier runs.
            commitAuthority: (state) => {
              currentOwnerId = state.ownerId;
              ownerAuthorityEstablished = state.established;
            },
            revokeAndClear: (previousOwnerId) => terminalizeAndClearOwnerRuntime(
              previousOwnerId,
              "owner_state_cleared",
            ),
          });
          const receipt = barrier.receipt;
          send({
            type: "owner_runtime_revoked",
            protocolVersion: request.protocolVersion,
            requestId,
            clientId,
            ownerId: receipt.ownerId,
            ok: true,
            duplicate: barrier.duplicate,
            revokedRunIds: receipt.revokedRunIds,
            invalidatedBindingIds: receipt.invalidatedBindingIds,
          });
        } catch (error) {
          send({
            type: "owner_runtime_revoked",
            protocolVersion: request.protocolVersion,
            requestId,
            clientId,
            ownerId: requestedOwnerId,
            ok: false,
            duplicate: false,
            revokedRunIds: [],
            invalidatedBindingIds: [],
            error: externalAuthorityError(error, "owner_runtime_revoke_failed"),
          });
        }
        break;
      }

      case "invalidate_session": {
        const invalidate = msg as InvalidateSessionMessage;
        invalidate.ownerId = resolveActiveOwner(invalidate.ownerId);
        transport.handleInvalidateSession(invalidate);
        break;
      }

      case "refresh_owner": {
        const owner = msg as RefreshOwnerMessage;
        const transition = establishRuntimeOwner(
          { ownerId: currentOwnerId, established: ownerAuthorityEstablished },
          owner.ownerId,
        );
        if (transition.changed && !transition.firstEstablishment) {
          currentOwnerId = DEFAULT_LOCAL_OWNER_ID;
          ownerAuthorityEstablished = false;
          terminalizeAndClearOwnerRuntime(transition.previousOwnerId, "owner_changed");
        }
        currentOwnerId = transition.ownerId;
        ownerAuthorityEstablished = true;
        lastOwnerRuntimeRevocation = null;
        if (transition.changed || transition.firstEstablishment) {
        }
        break;
      }

      case "refresh_token": {
        const rtm = msg as RefreshTokenMessage;
        const transition = authorizeRuntimeTokenRefresh(
          { ownerId: currentOwnerId, established: ownerAuthorityEstablished },
          rtm.ownerId,
          () => { process.env.OMI_AUTH_TOKEN = rtm.token; },
        );
        if (transition.changed) {
          directControlExecutions.transitionOwner(transition.previousOwnerId, transition.ownerId);
          kernel.revokeRunToolCapabilitiesForOwner(transition.previousOwnerId, "owner_changed");
          rejectPendingToolCallsForOwner(transition.previousOwnerId);
        }
        currentOwnerId = transition.ownerId;
        ownerAuthorityEstablished = true;
        lastOwnerRuntimeRevocation = null;
        if (transition.changed || transition.firstEstablishment) {
        }
        try {
          await ensurePiMonoAdapter(rtm.token);
          for (const adapter of piMonoAdapters) {
            const restarted = await adapter.updateAuthToken(rtm.token);
            if (restarted) {
              logErr("Pi-mono: token refresh restarted subprocess");
            }
          }
        } catch (err) {
          logErr(`Pi-mono token refresh error: ${err}`);
        }
        break;
      }

      case "stop":
        logErr("Received stop signal, exiting");
        directControlExecutions.abortAll();
        kernel.revokeRunToolCapabilities("runtime_stopped");
        rejectPendingToolCallsForOwner(
          currentOwnerId,
          "runtime_stopped",
          "Agent runtime stopped during tool execution",
        );
        store.close();
        await Promise.all([...piMonoAdapters].map((adapter) => adapter.stop()));
        process.exit(0);
        break;

      default:
        logErr(`Unknown message type: ${(msg as any).type}`);
      }
    } catch (error) {
      const request = msg as { protocolVersion?: unknown; requestId?: unknown; clientId?: unknown };
      const requestId = typeof request.requestId === "string" ? request.requestId : undefined;
      const clientId = typeof request.clientId === "string" ? request.clientId : undefined;
      const envelope = runtimeErrorEnvelope(error);
      if (isInboundResponseMessage(msg)) {
        logErr(`Unhandled runtime response error type=${msg.type}: ${envelope.message}`);
        return;
      }
      if (requestId && clientId) {
        send({
          type: "error",
          protocolVersion: PROTOCOL_VERSION,
          requestId,
          clientId,
          message: envelope.message,
          failure: envelope.failure,
        });
      } else {
        logErr(`Unhandled uncorrelated runtime request error: ${envelope.message}`);
      }
    }
  });

  rl.on("close", () => {
    logErr("stdin closed, exiting");
    logCrash("stdin closed, exiting");
    directControlExecutions.abortAll();
    kernel.revokeRunToolCapabilities("runtime_stopped");
    rejectPendingToolCallsForOwner(
      currentOwnerId,
      "runtime_stopped",
      "Agent runtime stopped during tool execution",
    );
    store.close();
    void Promise.all([...piMonoAdapters].map((adapter) => adapter.stop()));
    process.exit(0);
  });
}

main().catch((err) => {
  logErr(`Fatal error: ${err}`);
  logCrash(`Fatal error: ${err}`);
  const envelope = runtimeErrorEnvelope(err);
  send({ type: "error", message: envelope.message, failure: envelope.failure });
  process.exit(1);
});
