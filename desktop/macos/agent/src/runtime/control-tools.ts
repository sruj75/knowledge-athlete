import { createHash, randomUUID } from "node:crypto";
import { AsyncLocalStorage } from "node:async_hooks";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { z } from "zod";
import type {
  AgentArtifact,
  AgentDelegation,
  AgentEvent,
  AgentRun,
  AgentSession,
  AdapterBinding,
  RunAttempt,
} from "./types.js";
import { AgentRuntimeKernel, type DesktopAwarenessSnapshot, type ExecuteAgentRunInput } from "./kernel.js";
import { serializeArtifact } from "./artifact-serialization.js";
import { defaultArtifactRoot } from "./artifact-storage.js";
import { assertToolResultEnvelope, makeToolResultEnvelope, type ToolResultEnvelope } from "./tool-result-envelope.js";
import { agentControlCapabilityManifest, agentControlInputSchema } from "./control-tool-manifest.js";
import {
  parseAgentSpawnProducerJournalDescriptor,
  type AgentSpawnProducerJournalDescriptor,
} from "./agent-spawn-journal.js";
import { evaluateDesktopToolPolicy } from "./desktop-tool-policy.js";
import type { DesktopCoordinatorBundle } from "./desktop-tool-policy.js";
import {
  executionRoleAllowsTool,
  LEAF_AGENT_CONTROL_TOOLS,
  providerBoundaryForAdapter,
  resolveAdapterWithinBoundary,
  type AgentExecutionRole,
  type ProviderBoundary,
} from "./execution-policy.js";

const sessionStatusSchema = z.enum(["open", "archived", "closed"]);
const terminalRunStatuses = new Set(["succeeded", "failed", "cancelled", "timed_out", "orphaned"]);
const agentSurfaceKindSchema = z.enum([
  "main_chat",
  "realtime",
  "delegated_agent",
  "background_agent",
  "floating_bar",
  "floating_pill",
]);
const originSurfaceKindSchema = z.enum([
  "main_chat",
  "floating_bar",
  "realtime",
  "agent_control",
]);
const artifactRoleSchema = z.enum(["input", "result", "checkpoint", "tool_output", "log", "other"]);
const artifactLifecycleStateSchema = z.enum(["retained", "dismissed", "opened"]);
const runModeSchema = z.enum(["ask", "act"]);
const delegationModeSchema = z.enum(["call", "spawn", "continue"]);
const desktopCoordinatorBundleSchema = z.enum([
  "desktop.agent_control.read",
  "desktop.agent_control.manage",
  "desktop.context.local_read",
  "desktop.context.screen_summary",
  "desktop.context.screenshot_image",
  "desktop.tasks.readwrite",
  "desktop.artifacts.manage",
  "desktop.automation.read",
  "desktop.automation.act_dev_only",
  "external.write_prepare",
  "external.write_send",
]);
const strictObject = <T extends z.ZodRawShape>(shape: T) => z.object(shape).strict();

const listAgentSessionsSchema = strictObject({
  ownerId: z.string().min(1).optional(),
  status: sessionStatusSchema.optional(),
  surfaceKind: agentSurfaceKindSchema.optional(),
  limit: z.coerce.number().int().positive().max(200).default(50),
  beforeUpdatedAtMs: z.coerce.number().int().positive().optional(),
});

const getAgentRunSchema = strictObject({
  runId: z.string().min(1),
  ownerId: z.string().min(1).optional(),
  includeEvents: z.boolean().default(true),
  eventLimit: z.coerce.number().int().positive().max(500).default(100),
});

const buildDesktopAwarenessSnapshotSchema = strictObject({
  ownerId: z.string().min(1).optional(),
  limit: z.coerce.number().int().positive().max(200).default(50),
});

const listDesktopActionQueueSchema = strictObject({
  ownerId: z.string().min(1).optional(),
  staleAfterMs: z.coerce.number().int().positive().optional(),
  limit: z.coerce.number().int().positive().max(200).default(50),
});

const contextSnippetSchema = strictObject({
  snippetId: z.string().min(1),
  sourceKind: z.enum([
    "omi_db",
    "rewind_timeline",
    "screen_current",
    "screenshot_image",
    "local_agent_api",
    "automation_bridge",
    "chat_surface",
  ]),
  operation: z.string().min(1),
  provenance: z.record(z.string(), z.unknown()).default({}),
  content: z.string().optional(),
  redactedContent: z.string().optional(),
  metadata: z.record(z.string(), z.unknown()).default({}),
  sensitivityTier: z.string().min(1),
  policyDecision: z.enum(["allowed", "denied", "dispatch_created"]).optional(),
  dispatchId: z.string().min(1).nullable().optional(),
  selected: z.boolean().optional(),
  tokenEstimate: z.coerce.number().int().positive().optional(),
});

const buildDesktopContextPacketSchema = strictObject({
  ownerId: z.string().min(1).optional(),
  sessionId: z.string().min(1).nullable().optional(),
  runId: z.string().min(1).nullable().optional(),
  surfaceKind: z.string().min(1),
  objective: z.string().min(1),
  packetJson: strictObject({
    snippets: z.array(contextSnippetSchema).default([]),
    selectedToolBundles: z.array(desktopCoordinatorBundleSchema).default([]),
    constraints: z.array(z.string()).default([]),
    evidenceRequired: z.array(z.string()).default([]),
    boundaryPolicy: z.record(z.string(), z.unknown()).default({}),
  }),
  ttlMs: z.coerce.number().int().positive(),
  retentionClass: z.enum(["ephemeral", "debug", "core"]),
});

const desktopIntentSyntaxFactsSchema = strictObject({
  delegationNegated: z.boolean().optional(),
  explicitSessionId: z.string().min(1).nullable().optional(),
  explicitRunId: z.string().min(1).nullable().optional(),
  parentRunId: z.string().min(1).nullable().optional(),
  requestedAgentCount: z.coerce.number().int().positive().nullable().optional(),
});

const desktopIntentProposalSchema = z.discriminatedUnion("intent", [
  strictObject({ intent: z.literal("answer_inline") }),
  strictObject({ intent: z.literal("spawn_agent") }),
  strictObject({ intent: z.literal("continue_run") }),
  strictObject({
    intent: z.literal("clarify"),
    missing: z.array(z.string().min(1)).max(10).optional(),
  }),
]);

const routeDesktopIntentSchema = strictObject({
  ownerId: z.string().min(1).optional(),
  utterance: z.string().min(1),
  surfaceKind: z.string().min(1),
  taskId: z.string().min(1).nullable().optional(),
  snapshotVersion: z.string().min(1).optional(),
  syntaxFacts: desktopIntentSyntaxFactsSchema.optional(),
  proposal: desktopIntentProposalSchema.optional(),
});

const evaluateDesktopToolPolicySchema = strictObject({
  // Direct app control authenticates the caller through an owner guard that is
  // merged into every strict control-tool input before dispatch.
  ownerId: z.string().min(1).optional(),
  toolName: z.string().min(1).optional(),
  selectedBundles: z.array(desktopCoordinatorBundleSchema),
  requestedBundles: z.array(desktopCoordinatorBundleSchema).optional(),
  sql: z.string().optional(),
  operation: z.string().optional(),
  resourceRef: z.string().optional(),
  includesScreenshotImageBytes: z.boolean().optional(),
  broadScreenHistory: z.boolean().optional(),
  externalSend: z.boolean().optional(),
  persistentGrant: z.boolean().optional(),
  isDevBundle: z.boolean().optional(),
});

const createDesktopDispatchSchema = strictObject({
  ownerId: z.string().min(1).optional(),
  kind: z.enum([
    "approval",
    "routing_choice",
    "failure_recovery",
    "artifact_review",
    "memory_candidate",
    "external_draft",
    "screen_context",
  ]),
  priority: z.coerce.number().int(),
  title: z.string().min(1),
  decisionPrompt: z.string().min(1),
  recommendedDefault: z.string().nullable().optional(),
  sourceSessionId: z.string().min(1).nullable().optional(),
  sourceRunId: z.string().min(1).nullable().optional(),
  sourceAttemptId: z.string().min(1).nullable().optional(),
  sourceArtifactId: z.string().min(1).nullable().optional(),
  capability: z.string().nullable().optional(),
  operation: z.string().nullable().optional(),
  resourceRef: z.string().nullable().optional(),
  payload: z.record(z.string(), z.unknown()).default({}),
  expiresAtMs: z.coerce.number().int().positive().nullable().optional(),
});

const resolveDesktopDispatchSchema = strictObject({
  dispatchId: z.string().min(1),
  ownerId: z.string().min(1).optional(),
  status: z.enum(["resolved", "cancelled"]),
  resolvedBy: z.string().nullable().optional(),
  resolution: z.record(z.string(), z.unknown()).default({}),
  grant: strictObject({
    sessionId: z.string().min(1).optional(),
    runId: z.string().min(1).nullable().optional(),
    capability: z.string().min(1),
    operation: z.string().min(1),
    resourcePattern: z.string().min(1),
    effect: z.enum(["allow", "deny"]).default("allow"),
    source: z.enum(["legacy_default", "policy", "user", "system"]).default("user"),
    constraintsJson: z.string().default("{}"),
    expiresAtMs: z.coerce.number().int().positive().nullable().optional(),
  }).optional(),
});

const cancelAgentRunSchema = strictObject({
  runId: z.string().min(1),
  ownerId: z.string().min(1).optional(),
});

const inspectAgentArtifactsSchema = z
  .strictObject({
    artifactId: z.string().min(1).optional(),
    sessionId: z.string().min(1).optional(),
    runId: z.string().min(1).optional(),
    attemptId: z.string().min(1).optional(),
    ownerId: z.string().min(1).optional(),
    role: artifactRoleSchema.optional(),
    limit: z.coerce.number().int().positive().max(200).default(50),
  })
  .refine((value) => value.artifactId || value.sessionId || value.runId || value.attemptId, {
    message: "Provide artifactId, sessionId, runId, or attemptId",
  });

const updateAgentArtifactLifecycleSchema = strictObject({
  artifactId: z.string().min(1),
  state: artifactLifecycleStateSchema,
  sessionId: z.string().min(1).optional(),
  runId: z.string().min(1).optional(),
  attemptId: z.string().min(1).optional(),
  ownerId: z.string().min(1).optional(),
  reason: z.string().min(1).max(500).optional(),
  metadata: z.record(z.string(), z.unknown()).default({}),
});

const readToolOutputSchema = strictObject({
  artifactId: z.string().min(1),
  ownerId: z.string().min(1).optional(),
  maxBytes: z.coerce.number().int().positive().max(8 * 1024).default(4 * 1024),
});

const searchToolOutputSchema = strictObject({
  artifactId: z.string().min(1),
  ownerId: z.string().min(1).optional(),
  query: z.string().min(1).max(256),
  maxMatches: z.coerce.number().int().positive().max(20).default(5),
});

const sendAgentMessageSchema = strictObject({
  sessionId: z.string().min(1),
  originSurfaceKind: originSurfaceKindSchema,
  ownerId: z.string().min(1).optional(),
  prompt: z.string().min(1),
  mode: runModeSchema.default("ask"),
  requestId: z.string().min(1).optional(),
  clientId: z.string().min(1).default("intentive-control-tools"),
  metadata: z.record(z.string(), z.unknown()).default({}),
});

const toolPolicySchema = strictObject({
  allowedToolNames: z.array(z.string().min(1)).max(64),
});

const spawnBackgroundAgentSchema = strictObject({
  prompt: z.string().min(1),
  originSurfaceKind: originSurfaceKindSchema,
  title: z.string().min(1).optional(),
  surfaceKind: z.string().min(1).default("floating_bar"),
  externalRefKind: z.string().min(1).optional(),
  externalRefId: z.string().min(1).optional(),
  ownerId: z.string().min(1).optional(),
  mode: runModeSchema.default("act"),
  requestId: z.string().min(1).optional(),
  clientId: z.string().min(1).default("intentive-control-tools"),
  metadata: z.record(z.string(), z.unknown()).default({}),
  toolPolicy: toolPolicySchema.optional(),
});

const spawnAgentPublicShape = {
  objective: z.string().min(1),
  // Gemini's realtime tool contract advertises this optional pill summary.
  // Keep it in the canonical strict parser so a valid provider tool call does
  // not fail before the child-admission boundary.
  brief: z.string().min(1).optional(),
  requestedAgentCount: z.coerce.number().int().min(1).max(8).default(1),
  parentRunId: z.string().min(1).optional(),
  visible: z.boolean().default(true),
  title: z.string().min(1).optional(),
  externalRefId: z.string().min(1).optional(),
  ownerId: z.string().min(1).optional(),
  requestId: z.string().min(1).optional(),
  clientId: z.string().min(1).default("intentive-control-tools"),
  metadata: z.record(z.string(), z.unknown()).default({}),
  toolPolicy: toolPolicySchema.optional(),
} as const;

const spawnAgentSchema = strictObject(spawnAgentPublicShape);

const authorizedSpawnAgentSchema = strictObject({
  ...spawnAgentPublicShape,
  originSurfaceKind: originSurfaceKindSchema,
});

const runAgentAndWaitSchema = strictObject({
  objective: z.string().min(1),
  parentRunId: z.string().min(1),
  originSurfaceKind: originSurfaceKindSchema,
  context: z.string().max(4000).optional(),
  ownerId: z.string().min(1).optional(),
  runMode: runModeSchema.default("ask"),
  requestId: z.string().min(1).optional(),
  clientId: z.string().min(1).default("intentive-control-tools"),
  maxDepth: z.coerce.number().int().min(1).max(5).default(3),
  maxBudgetUsd: z.coerce.number().positive().max(10).default(5),
  metadata: z.record(z.string(), z.unknown()).default({}),
});

const setDesktopAttentionOverrideSchema = strictObject({
  ownerId: z.string().min(1).optional(),
  subjectKind: z.string().min(1),
  subjectId: z.string().min(1),
  dismissed: z.boolean().default(true),
  hiddenUntilMs: z.coerce.number().int().positive().nullable().optional(),
  reason: z.string().min(1).optional(),
});

export const agentControlToolSchemas = {
  list_agent_sessions: listAgentSessionsSchema,
  get_agent_run: getAgentRunSchema,
  build_desktop_awareness_snapshot: buildDesktopAwarenessSnapshotSchema,
  list_desktop_action_queue: listDesktopActionQueueSchema,
  build_desktop_context_packet: buildDesktopContextPacketSchema,
  route_desktop_intent: routeDesktopIntentSchema,
  evaluate_desktop_tool_policy: evaluateDesktopToolPolicySchema,
  create_desktop_dispatch: createDesktopDispatchSchema,
  resolve_desktop_dispatch: resolveDesktopDispatchSchema,
  cancel_agent_run: cancelAgentRunSchema,
  inspect_agent_artifacts: inspectAgentArtifactsSchema,
  read_tool_output: readToolOutputSchema,
  search_tool_output: searchToolOutputSchema,
  update_agent_artifact_lifecycle: updateAgentArtifactLifecycleSchema,
  send_agent_message: sendAgentMessageSchema,
  spawn_background_agent: spawnBackgroundAgentSchema,
  spawn_agent: spawnAgentSchema,
  run_agent_and_wait: runAgentAndWaitSchema,
  set_desktop_attention_override: setDesktopAttentionOverrideSchema,
} as const;

export type AgentControlToolName = keyof typeof agentControlToolSchemas;

export const INTERNAL_AGENT_CONTROL_TOOL_NAMES = [] as const satisfies readonly AgentControlToolName[];

export const AGENT_CONTROL_TOOL_NAMES = agentControlCapabilityManifest.map(
  (tool) => tool.name,
) as AgentControlToolName[];

/** App-callable tools advertised to Swift; internal continuity RPCs stay out of model manifests. */
export const SWIFT_ADVERTISED_AGENT_CONTROL_TOOL_NAMES = [
  ...AGENT_CONTROL_TOOL_NAMES.filter((name) => name !== "spawn_background_agent"),
  ...INTERNAL_AGENT_CONTROL_TOOL_NAMES,
] as AgentControlToolName[];

const CONTROL_TOOL_NAME_SET = new Set<string>(Object.keys(agentControlToolSchemas));

/**
 * The final provider-result boundary needs the authoritative tool identity and
 * artifact owner even for early validation and catch paths. AsyncLocalStorage
 * keeps that authority with the request across awaited tool effects without
 * asking every individual switch branch to remember a serialization step.
 */
interface ControlToolOutputScope {
  context: AgentControlToolContext;
  toolName: string;
}

const controlToolOutputScope = new AsyncLocalStorage<ControlToolOutputScope>();

export interface AgentControlToolDefinition {
  name: AgentControlToolName;
  description: string;
  inputSchema: Record<string, unknown>;
}

export const agentControlToolDefinitions: AgentControlToolDefinition[] = agentControlCapabilityManifest.map((tool) => ({
  name: tool.name,
  description: tool.description,
  inputSchema: agentControlInputSchema(tool),
}));

export interface AgentControlToolContext {
  kernel: AgentRuntimeKernel;
  /**
   * The adapter selected by the owning desktop surface.  New background work
   * must inherit this route rather than silently selecting a local provider.
   */
  defaultAdapterId?: string;
  /** Private artifacts directory fixed by the desktop runtime. */
  workingDirectory?: string;
  /** Kernel-owned provider and role policy for the active control caller. */
  providerBoundary?: ProviderBoundary;
  executionRole?: AgentExecutionRole;
  /** Persisted caller session used for kernel-level spawn authority checks. */
  callerSessionId?: string;
  /** Kernel-synthesized authority; never copied from adapter/model metadata. */
  authorizedProducerJournal?: AgentSpawnProducerJournalDescriptor;
  authorizedCallerRunId?: string;
  /** Exact kernel capability identity for a model-visible control-tool result. */
  authorizedToolInvocation?: {
    invocationId: string;
    runId: string;
    attemptId: string;
    toolName: string;
  };
  trustedUserControl?: boolean;
  getOwnerId?: () => string;
  /** Broker-owned authority checked immediately around every physical effect. */
  executionLease?: {
    readonly signal: AbortSignal;
    assertCurrentAuthority(): void | Promise<void>;
    /** Direct desktop control retains admitted children through owner transition. */
    retainRun?(runId: string): void;
  };
  recoverRunInput?: (adapterId: string) => Pick<ExecuteAgentRunInput, "maxAttempts" | "recoverAfterError">;
}

interface PartialAgentSpawnCancellation {
  runId: string;
  accepted?: boolean;
  dispatchAttempted?: boolean;
  adapterAcknowledged?: boolean;
  error?: string;
}

class PartialAgentSpawnError extends Error {
  readonly code: string;
  readonly details: {
    admittedRunIds: string[];
    cancellations: PartialAgentSpawnCancellation[];
    cause: string;
  };

  constructor(input: {
    cause: unknown;
    cancellations: PartialAgentSpawnCancellation[];
  }) {
    const causeMessage = input.cause instanceof Error ? input.cause.message : String(input.cause);
    const cleanupFailed = input.cancellations.some((cancellation) => cancellation.error !== undefined);
    const causeCode = input.cause && typeof input.cause === "object" && "code" in input.cause
      ? String((input.cause as { code: unknown }).code)
      : "";
    super(cleanupFailed
      ? `Agent spawn failed after admitting children, and compensation failed for at least one child: ${causeMessage}`
      : `Agent spawn failed after admitting children; every admitted child was cancelled: ${causeMessage}`);
    this.name = "PartialAgentSpawnError";
    this.code = /^[a-z0-9_]{1,64}$/.test(causeCode)
      ? causeCode
      : cleanupFailed ? "partial_spawn_cleanup_failed" : "partial_spawn_compensated";
    this.details = {
      admittedRunIds: input.cancellations.map((cancellation) => cancellation.runId),
      cancellations: input.cancellations,
      cause: causeMessage,
    };
  }
}

function controlRunRecovery(
  context: AgentControlToolContext,
  adapterId: string,
): Pick<ExecuteAgentRunInput, "maxAttempts" | "recoverAfterError"> {
  return context.recoverRunInput?.(adapterId) ?? {};
}

function defaultControlAdapterId(context: AgentControlToolContext): string {
  return context.defaultAdapterId ?? "pi-mono";
}

function controlSpawnProfile(
  context: AgentControlToolContext,
  ownerId: string,
): { adapterId: string; modelProfile: string | null; workingDirectory: string | undefined } {
  if (context.callerSessionId) {
    const profile = context.kernel.sessionExecutionProfile(context.callerSessionId, ownerId);
    return {
      adapterId: profile.adapterId,
      modelProfile: profile.modelProfile,
      workingDirectory: profile.workingDirectory || undefined,
    };
  }
  return {
    adapterId: defaultControlAdapterId(context),
    modelProfile: "gemini-3.7-flash",
    workingDirectory: context.workingDirectory,
  };
}

function assertAdapterAllowedForControlRun(context: AgentControlToolContext, adapterId: string): void {
  if (!context.defaultAdapterId && !context.providerBoundary) {
    return;
  }
  const owningAdapterId = defaultControlAdapterId(context);
  resolveAdapterWithinBoundary({
    providerBoundary: context.providerBoundary ?? providerBoundaryForAdapter(owningAdapterId),
    defaultAdapterId: owningAdapterId,
    requestedAdapterId: adapterId,
  });
}

function assertAgentSpawningAllowed(context: AgentControlToolContext): void {
  if (context.executionRole === "leaf") {
    throw new Error("Background agents are leaf workers and cannot start additional agents.");
  }
}

function assertLeafControlToolsAllowed(context: AgentControlToolContext, name: string): void {
  if (!LEAF_AGENT_CONTROL_TOOLS.has(name)) return;
  if (!executionRoleAllowsTool(context.executionRole ?? "coordinator", name)) {
    throw new Error(
      name === "send_agent_message"
        ? "Leaf workers cannot continue agent sessions."
        : "Background agents are leaf workers and cannot start additional agents.",
    );
  }
}

function backgroundSpawnAuthority(context: AgentControlToolContext): {
  callerSessionId?: string;
  trustedUserSpawn?: boolean;
} {
  if (context.callerSessionId) {
    return { callerSessionId: context.callerSessionId };
  }
  if (context.trustedUserControl === true || context.executionRole !== "leaf") {
    return { trustedUserSpawn: true };
  }
  return {};
}

export const DEFAULT_LOCAL_OWNER_ID = "desktop-local-user";

export function withDefaultOwnerGuard(input: Record<string, unknown>, ownerGuard: string): Record<string, unknown> {
  if (Object.hasOwn(input, "ownerId")) {
    return input;
  }
  return { ...input, ownerId: ownerGuard };
}

export function withMergedOwnerGuard(
  input: Record<string, unknown>,
  ownerGuard: string | undefined,
  defaultOwnerGuard: string,
): Record<string, unknown> {
  if (!ownerGuard) {
    return withDefaultOwnerGuard(input, defaultOwnerGuard);
  }
  if (!Object.hasOwn(input, "ownerId")) {
    return { ...input, ownerId: ownerGuard };
  }
  const inputOwnerId = typeof input.ownerId === "string" ? input.ownerId.trim() : undefined;
  if (inputOwnerId !== ownerGuard) {
    throw new Error("Owner guards do not match");
  }
  return { ...input, ownerId: ownerGuard };
}

export function isAgentControlToolName(name: string): name is AgentControlToolName {
  return CONTROL_TOOL_NAME_SET.has(name);
}

async function executeAuthorizedControlEffect<T>(
  context: AgentControlToolContext,
  effect: () => T | Promise<T>,
): Promise<T> {
  await context.executionLease?.assertCurrentAuthority();
  if (context.executionLease?.signal.aborted) {
    throw context.executionLease.signal.reason instanceof Error
      ? context.executionLease.signal.reason
      : new Error("Run tool execution authority was revoked");
  }
  const result = await effect();
  await context.executionLease?.assertCurrentAuthority();
  return result;
}

export async function handleAgentControlToolCall(
  context: AgentControlToolContext,
  name: string,
  input: Record<string, unknown>,
): Promise<string> {
  return controlToolOutputScope.run({ context, toolName: name }, async () => {
    if (!isAgentControlToolName(name)) {
      return stringifyToolResult({
        error: {
          code: "unknown_control_tool",
          message: `Unknown control tool: ${name}`,
        },
      }, "failed");
    }
    if (name === "resolve_desktop_dispatch" && !context.trustedUserControl) {
      return stringifyToolResult({
        error: {
          code: "policy_denied",
          message: "resolve_desktop_dispatch requires trusted user control",
        },
      }, "failed");
    }

    try {
    assertLeafControlToolsAllowed(context, name);
    switch (name) {
      case "list_agent_sessions": {
        const parsed = agentControlToolSchemas.list_agent_sessions.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        // `background_agent` and `delegated_agent` describe execution intent,
        // not persisted session surfaces. Realtime models naturally choose
        // those semantic labels when asked about a child result; passing them
        // through as exact surface filters hides valid concrete surfaces such
        // as `floating_bar`. Treat them as leaf-role discovery aliases so a
        // newer coordinator session cannot win a small result limit.
        const isChildDiscovery = parsed.surfaceKind === "background_agent"
          || parsed.surfaceKind === "delegated_agent";
        // `closed` is an archival session state, not a child-run completion
        // state. Older realtime tool schemas exposed that enum, and models
        // naturally chose `closed` while asking for a finished background
        // agent's output. Preserve that intent only for the semantic child
        // discovery aliases; concrete session-management callers keep the
        // literal archival filter.
        const legacyClosedChildDiscovery = isChildDiscovery && parsed.status === "closed";
        const discoveredSessions = context.kernel.listSessions({
          ...parsed,
          ownerId,
          status: legacyClosedChildDiscovery ? undefined : parsed.status,
          surfaceKind: isChildDiscovery ? undefined : parsed.surfaceKind,
          executionRole: isChildDiscovery ? "leaf" : undefined,
          limit: legacyClosedChildDiscovery ? 200 : parsed.limit,
        });
        const sessions = legacyClosedChildDiscovery
          ? discoveredSessions
            .filter((summary) => terminalRunStatuses.has((summary.activeRun ?? summary.latestRun)?.status ?? ""))
            .slice(0, parsed.limit)
          : discoveredSessions;
        const overrides = context.kernel.listDesktopAttentionOverrides(ownerId);
        const projected = serializeAgentSessionsList(sessions, overrides);
        return stringifyToolResult(withToolResultEnvelope(
          context,
          "list_agent_sessions",
          serializeFullSessionListing(sessions, projected),
          projected,
          ownerId,
          context.callerSessionId ?? sessions[0]?.session.sessionId,
        ));
      }
      case "get_agent_run": {
        const parsed = agentControlToolSchemas.get_agent_run.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const details = context.kernel.getRun({
          ...parsed,
          ownerId,
        });
        const full = serializeRunDetails(details);
        return stringifyToolResult(withToolResultEnvelope(
          context,
          "get_agent_run",
          full,
          projectProviderPayload(full, "get_agent_run"),
          ownerId,
          details.session.sessionId,
        ));
      }
      case "build_desktop_awareness_snapshot": {
        const parsed = agentControlToolSchemas.build_desktop_awareness_snapshot.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const snapshot = context.kernel.buildDesktopAwarenessSnapshot({
          ...parsed,
          ownerId,
        });
        const serializedSnapshot = serializeAwarenessSnapshot(snapshot);
        const full = { snapshot: serializedSnapshot };
        // The realtime provider needs an artifact-backed preview, while the
        // local Swift coordinator needs owner/session/run roots it can use to
        // reconcile visible pills. A generic depth-limited preview can omit
        // `ownerId` and turn a valid read into a false lifecycle failure.
        const providerProjection = projectProviderPayload(full, "build_desktop_awareness_snapshot");
        return stringifyToolResult(withToolResultEnvelope(
          context,
          "build_desktop_awareness_snapshot",
          full,
          providerProjection,
          ownerId,
          context.callerSessionId ?? snapshot.sessions[0]?.session.sessionId,
          undefined,
          projectDirectControlAwarenessSnapshot(snapshot),
        ));
      }
      case "list_desktop_action_queue": {
        const parsed = agentControlToolSchemas.list_desktop_action_queue.parse(input);
        const actionQueue = context.kernel.listDesktopActionQueue({
          ...parsed,
          ownerId: effectiveControlToolOwnerId(context, parsed.ownerId),
        });
        return stringifyToolResult({ actionQueue });
      }
      case "build_desktop_context_packet": {
        const parsed = agentControlToolSchemas.build_desktop_context_packet.parse(input);
        const built = await executeAuthorizedControlEffect(context, () =>
          context.kernel.persistDesktopContextPacket({
            ownerId: effectiveControlToolOwnerId(context, parsed.ownerId),
            sessionId: parsed.sessionId ?? null,
            runId: parsed.runId ?? null,
            surfaceKind: parsed.surfaceKind,
            objective: parsed.objective,
            snippets: parsed.packetJson.snippets,
            selectedToolBundles: parsed.packetJson.selectedToolBundles,
            constraints: parsed.packetJson.constraints,
            evidenceRequired: parsed.packetJson.evidenceRequired,
            boundaryPolicy: parsed.packetJson.boundaryPolicy,
            ttlMs: parsed.ttlMs,
            retentionClass: parsed.retentionClass,
          }));
        return stringifyToolResult({
          packet: {
            ...built.packet,
            packetJson: built.packet.packetJson,
            redactedPreviewJson: built.packet.redactedPreviewJson,
          },
          accessLogs: built.accessLogs,
        });
      }
      case "route_desktop_intent": {
        const parsed = agentControlToolSchemas.route_desktop_intent.parse(input);
        const route = context.kernel.routeDesktopIntent({
          ...parsed,
          ownerId: effectiveControlToolOwnerId(context, parsed.ownerId),
          callerSessionId: context.callerSessionId,
          taskId: parsed.taskId ?? null,
        });
        return stringifyToolResult({ route });
      }
      case "evaluate_desktop_tool_policy": {
        const parsed = agentControlToolSchemas.evaluate_desktop_tool_policy.parse(input);
        const policy = evaluateDesktopToolPolicy({
          ...parsed,
          selectedBundles: parsed.selectedBundles as DesktopCoordinatorBundle[],
          requestedBundles: parsed.requestedBundles as DesktopCoordinatorBundle[] | undefined,
        });
        return stringifyToolResult({ policy });
      }
      case "create_desktop_dispatch": {
        const parsed = agentControlToolSchemas.create_desktop_dispatch.parse(input);
        const dispatch = await executeAuthorizedControlEffect(context, () => context.kernel.createDesktopDispatch({
          ...parsed,
          ownerId: effectiveControlToolOwnerId(context, parsed.ownerId),
          payloadJson: JSON.stringify(parsed.payload),
        }));
        return stringifyToolResult({ dispatch });
      }
      case "resolve_desktop_dispatch": {
        const parsed = agentControlToolSchemas.resolve_desktop_dispatch.parse(input);
        const result = await executeAuthorizedControlEffect(context, () => context.kernel.resolveDesktopDispatch(parsed.dispatchId, {
          ownerId: effectiveControlToolOwnerId(context, parsed.ownerId),
          status: parsed.status,
          resolvedBy: parsed.resolvedBy ?? "user",
          resolutionJson: JSON.stringify(parsed.resolution),
          grant: parsed.grant,
        }));
        return stringifyToolResult({
          dispatch: result.dispatch,
          grant: result.grant,
          event: result.event ? serializeEvent(result.event) : null,
        });
      }
      case "cancel_agent_run": {
        const parsed = agentControlToolSchemas.cancel_agent_run.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const cancellation = await executeAuthorizedControlEffect(context, () =>
          context.kernel.cancelRun(parsed.runId, { ownerId }));
        const details = context.kernel.getRun({
          runId: parsed.runId,
          ownerId,
          includeEvents: true,
          eventLimit: 100,
        });
        return stringifyToolResult({
          cancellation,
          run: serializeRun(details.run),
          attempts: details.attempts.map(serializeAttempt),
        });
      }
      case "inspect_agent_artifacts": {
        const parsed = agentControlToolSchemas.inspect_agent_artifacts.parse(input);
        const artifacts = context.kernel.inspectArtifacts({
          ...parsed,
          ownerId: effectiveControlToolOwnerId(context, parsed.ownerId),
        });
        return stringifyToolResult({
          artifacts: artifacts.map(serializeArtifact),
        });
      }
      case "read_tool_output": {
        const parsed = agentControlToolSchemas.read_tool_output.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const artifact = readToolOutputArtifact(context, parsed.artifactId, ownerId);
        const fullText = readLocalArtifactText(artifact.uri);
        const projectedText = truncateUtf8(fullText, parsed.maxBytes);
        return stringifyToolResult(withToolResultEnvelope(
          context,
          "read_tool_output",
          { artifactId: artifact.artifactId, output: fullText, truncated: false },
          { artifactId: artifact.artifactId, output: projectedText.text, truncated: projectedText.truncated },
          ownerId,
          artifact.sessionId,
          `artifact:${artifact.artifactId}`,
        ));
      }
      case "search_tool_output": {
        const parsed = agentControlToolSchemas.search_tool_output.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const artifact = readToolOutputArtifact(context, parsed.artifactId, ownerId);
        const fullText = readLocalArtifactText(artifact.uri);
        const needle = parsed.query.toLocaleLowerCase();
        const matches = fullText.split(/\r?\n/)
          .filter((line) => line.toLocaleLowerCase().includes(needle))
          .slice(0, parsed.maxMatches)
          .map((line) => truncateUtf8(line, 512).text);
        return stringifyToolResult(withToolResultEnvelope(
          context,
          "search_tool_output",
          { artifactId: artifact.artifactId, matches, matchCount: matches.length, fullOutput: fullText },
          { artifactId: artifact.artifactId, matches, matchCount: matches.length },
          ownerId,
          artifact.sessionId,
          `artifact:${artifact.artifactId}`,
        ));
      }
      case "update_agent_artifact_lifecycle": {
        const parsed = agentControlToolSchemas.update_agent_artifact_lifecycle.parse(input);
        const result = await executeAuthorizedControlEffect(context, () => context.kernel.updateArtifactLifecycle({
          ...parsed,
          ownerId: effectiveControlToolOwnerId(context, parsed.ownerId),
        }));
        return stringifyToolResult({
          artifact: serializeArtifact(result.artifact),
          changed: result.changed,
          event: result.event ? serializeEvent(result.event) : null,
        });
      }
      case "send_agent_message": {
        const parsed = agentControlToolSchemas.send_agent_message.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const targetPolicy = context.kernel.executionPolicyForOwnedSession(parsed.sessionId, ownerId);
        const adapterId = targetPolicy.defaultAdapterId;
        assertAdapterAllowedForControlRun(context, adapterId);
        rejectSynchronousNestedRun(context, adapterId, parsed.sessionId);
        const requestId = parsed.requestId ?? `send-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        const routed = await executeAuthorizedControlEffect(context, () => context.kernel.applyDesktopIntentEffect(
          {
            ownerId,
            callerSessionId: context.callerSessionId,
            restrictiveCallerExecutionRole: context.executionRole,
            surfaceKind: parsed.originSurfaceKind,
            snapshotVersion: controlRouteSnapshotVersion(parsed.metadata),
            utterance: parsed.prompt,
            effect: "continue_run",
            syntaxFacts: {
              explicitSessionId: parsed.sessionId,
            },
          },
          () => context.kernel.sendAgentMessage({
            ...parsed,
            ...controlRunRecovery(context, adapterId),
            ownerId,
            requestId,
            metadata: { ...(parsed.metadata ?? {}) },
            authoritySignal: context.executionLease?.signal,
          }),
        ));
        const result = routed.result;
        return stringifyToolResult({
          routeDecision: routed.decision,
          session: serializeSession(result.session),
          run: serializeRun(result.run),
          attempt: serializeAttempt(result.attempt),
          adapterSessionId: result.adapterSessionId,
          terminalStatus: result.terminalStatus,
          text: result.text,
          artifacts: result.artifacts.map(serializeArtifact),
        });
      }
      case "spawn_background_agent": {
        assertAgentSpawningAllowed(context);
        const parsed = agentControlToolSchemas.spawn_background_agent.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const requestId = parsed.requestId ?? `background-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        const spawnProfile = controlSpawnProfile(context, ownerId);
        const adapterId = spawnProfile.adapterId;
        const cwd = spawnProfile.workingDirectory;
        const model = spawnProfile.modelProfile ?? undefined;
        assertAdapterAllowedForControlRun(context, adapterId);
        const routed = await executeAuthorizedControlEffect(context, () => context.kernel.applyDesktopIntentEffect(
          {
            ownerId,
            callerSessionId: context.callerSessionId,
            restrictiveCallerExecutionRole: context.executionRole,
            surfaceKind: parsed.originSurfaceKind,
            snapshotVersion: controlRouteSnapshotVersion(parsed.metadata),
            utterance: parsed.prompt,
            effect: "spawn_agent",
            syntaxFacts: {
              requestedAgentCount: 1,
            },
          },
          () => context.kernel.spawnBackgroundAgent({
            ...parsed,
            ...controlRunRecovery(context, adapterId),
            ...backgroundSpawnAuthority(context),
            adapterId,
            defaultAdapterId: adapterId,
            cwd,
            model,
            ownerId,
            requestId,
            surfaceKind: parsed.surfaceKind ?? "floating_bar",
            metadata: { ...(parsed.metadata ?? {}) },
            authoritySignal: context.executionLease?.signal,
          }),
        ));
        const result = routed.result;
        context.executionLease?.retainRun?.(result.run.runId);
        return stringifyToolResult({
          routeDecision: routed.decision,
          session: serializeSession(result.session),
          run: serializeRun(result.run),
          attempt: result.attempt ? serializeAttempt(result.attempt) : null,
        });
      }
      case "spawn_agent": {
        assertAgentSpawningAllowed(context);
        const parsed = authorizedSpawnAgentSchema.parse(input);
        const callerMetadata = { ...(parsed.metadata ?? {}) };
        const proposedProducerJournal = callerMetadata.producerJournal;
        delete callerMetadata.producerJournal;
        let producerJournal = context.authorizedProducerJournal;
        if (!producerJournal && context.trustedUserControl && proposedProducerJournal !== undefined) {
          producerJournal = parseAgentSpawnProducerJournalDescriptor(proposedProducerJournal);
          if (producerJournal.producerTurnId) {
            throw new Error("producerTurnId is reserved for kernel-authorized spawn invocations");
          }
        }
        const parentRunId = context.authorizedCallerRunId ?? parsed.parentRunId;
        if (context.authorizedCallerRunId && parsed.parentRunId && parsed.parentRunId !== context.authorizedCallerRunId) {
          throw new Error("Agent spawn parent run does not match authorized caller run");
        }
        if (parentRunId) {
          assertCanonicalRunId(parentRunId, "parentRunId");
        }
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const spawnProfile = controlSpawnProfile(context, ownerId);
        const requestId = parsed.requestId ?? `spawn-agent-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        const adapterId = parentRunId
          ? context.kernel.defaultAdapterIdForRun(parentRunId)
          : spawnProfile.adapterId;
        const inheritsParentExecutionProfile = Boolean(parentRunId);
        const cwd = inheritsParentExecutionProfile ? undefined : spawnProfile.workingDirectory;
        const model = inheritsParentExecutionProfile ? undefined : spawnProfile.modelProfile ?? undefined;
        assertAdapterAllowedForControlRun(context, adapterId);
        const childSurfaceKind = parsed.visible ? "floating_bar" : "delegated_agent";
        const childExternalRefKind = parsed.visible ? "pill" : undefined;
        const producerContextSnapshot = !parentRunId && producerJournal
          ? context.kernel.contextSnapshotForExactSurface(ownerId, producerJournal.surface)
          : undefined;
        const routed = await context.kernel.applyDesktopIntentEffect(
          {
            ownerId,
            callerSessionId: context.callerSessionId,
            restrictiveCallerExecutionRole: context.executionRole,
            surfaceKind: parsed.originSurfaceKind,
            snapshotVersion: controlRouteSnapshotVersion(parsed.metadata),
            utterance: parsed.objective,
            effect: "spawn_agent",
            syntaxFacts: {
              parentRunId,
              requestedAgentCount: parsed.requestedAgentCount,
            },
          },
          async () => {
            const siblings: Array<
              | { kind: "delegated"; result: Awaited<ReturnType<AgentRuntimeKernel["delegateAgent"]>> }
              | { kind: "background"; result: Awaited<ReturnType<AgentRuntimeKernel["spawnBackgroundAgent"]>> }
            > = [];
            try {
              for (let index = 0; index < parsed.requestedAgentCount; index += 1) {
                const ordinal = index + 1;
                const siblingRequestId = parsed.requestedAgentCount === 1 ? requestId : `${requestId}:${ordinal}`;
                const siblingExternalRefId = parsed.visible
                  ? parsed.requestedAgentCount === 1
                    ? (parsed.externalRefId ?? randomUUID())
                    : randomUUID()
                  : parsed.externalRefId;
                const titleSuffix = parsed.requestedAgentCount === 1 ? "" : ` (${ordinal}/${parsed.requestedAgentCount})`;
                const childTitle = `${parsed.title ?? `${parentRunId ? "Delegated" : "Background"}: ${parsed.objective.slice(0, 80)}`}${titleSuffix}`;
                const siblingProducerJournal = producerJournal && siblingExternalRefId
                  ? {
                      ...producerJournal,
                      continuityKey: parsed.requestedAgentCount === 1
                        ? producerJournal.continuityKey
                        : `${producerJournal.continuityKey}:${ordinal}`,
                      pillId: siblingExternalRefId,
                      objective: parsed.objective,
                      title: childTitle,
                    }
                  : undefined;
                const siblingMetadata = {
                  ...callerMetadata,
                  visible: parsed.visible,
                  siblingOrdinal: ordinal,
                  ...(parsed.brief ? { brief: parsed.brief } : {}),
                  ...(parsed.requestedAgentCount > 1 && parsed.externalRefId
                    ? { siblingGroupExternalRefId: parsed.externalRefId }
                    : {}),
                  ...(parsed.visible && siblingExternalRefId ? { pillId: siblingExternalRefId } : {}),
                  ...(siblingProducerJournal ? { producerJournal: siblingProducerJournal } : {}),
                };
                if (inheritsParentExecutionProfile) {
                  if (!parentRunId) {
                    throw new Error("Parent-linked agent spawn is missing its parent run");
                  }
                  const result = await executeAuthorizedControlEffect(context, () => context.kernel.delegateAgent({
                    ...controlRunRecovery(context, adapterId ?? defaultControlAdapterId(context)),
                    mode: "spawn",
                    parentRunId,
                    objective: parsed.objective,
                    ownerId,
                    requestId: siblingRequestId,
                    adapterId,
                    defaultAdapterId: adapterId,
                    childSurfaceKind,
                    childExternalRefKind,
                    childExternalRefId: siblingExternalRefId,
                    childTitle,
                    cwd,
                    model,
                    runMode: "act",
                    clientId: parsed.clientId,
                    metadata: siblingMetadata,
                    toolPolicy: parsed.toolPolicy,
                    authoritySignal: context.executionLease?.signal,
                  }));
                  siblings.push({
                    kind: "delegated",
                    result,
                  });
                  context.executionLease?.retainRun?.(result.childRun.runId);
                } else {
                  const result = await executeAuthorizedControlEffect(context, () => context.kernel.spawnBackgroundAgent({
                    ...controlRunRecovery(context, adapterId ?? defaultControlAdapterId(context)),
                    ...backgroundSpawnAuthority(context),
                    ownerId,
                    clientId: parsed.clientId,
                    requestId: siblingRequestId,
                    prompt: parsed.objective,
                    title: childTitle,
                    surfaceKind: childSurfaceKind,
                    externalRefKind: childExternalRefKind,
                    externalRefId: siblingExternalRefId,
                    adapterId,
                    defaultAdapterId: adapterId,
                    cwd,
                    model,
                    mode: "act",
                    metadata: siblingMetadata,
                    toolPolicy: parsed.toolPolicy,
                    admittedContextSnapshot: producerContextSnapshot,
                    authoritySignal: context.executionLease?.signal,
                  }));
                  siblings.push({
                    kind: "background",
                    result,
                  });
                  context.executionLease?.retainRun?.(result.run.runId);
                }
              }
            } catch (error) {
              if (siblings.length === 0) throw error;
              const cancellations: PartialAgentSpawnCancellation[] = [];
              for (const sibling of siblings) {
                const runId = sibling.kind === "delegated"
                  ? sibling.result.childRun.runId
                  : sibling.result.run.runId;
                try {
                  const cancellation = await context.kernel.cancelRun(runId, { ownerId });
                  cancellations.push({
                    runId,
                    accepted: cancellation.accepted,
                    dispatchAttempted: cancellation.dispatchAttempted,
                    adapterAcknowledged: cancellation.adapterAcknowledged,
                  });
                } catch (cancellationError) {
                  cancellations.push({
                    runId,
                    error: cancellationError instanceof Error
                      ? cancellationError.message
                      : String(cancellationError),
                  });
                }
              }
              throw new PartialAgentSpawnError({ cause: error, cancellations });
            }
            return siblings;
          },
        );
        const agents = routed.result.map((sibling) => sibling.kind === "delegated"
          ? {
              kind: sibling.kind,
              delegation: serializeDelegation(sibling.result.delegation),
              session: serializeSession(sibling.result.childSession),
              run: serializeRun(sibling.result.childRun),
              attempt: sibling.result.childAttempt ? serializeAttempt(sibling.result.childAttempt) : null,
            }
          : {
              kind: sibling.kind,
              delegation: null,
              session: serializeSession(sibling.result.session),
              run: serializeRun(sibling.result.run),
              attempt: sibling.result.attempt ? serializeAttempt(sibling.result.attempt) : null,
            });
        const first = agents[0]!;
        return stringifyToolResult({
          routeDecision: routed.decision,
          requestedAgentCount: parsed.requestedAgentCount,
          agents,
          delegation: first.delegation,
          session: first.session,
          run: first.run,
          attempt: first.attempt,
        });
      }
      case "run_agent_and_wait": {
        assertAgentSpawningAllowed(context);
        const parsed = agentControlToolSchemas.run_agent_and_wait.parse(input);
        assertCanonicalRunId(parsed.parentRunId, "parentRunId");
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const requestId = parsed.requestId ?? `run-and-wait-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        const adapterId = context.kernel.defaultAdapterIdForRun(parsed.parentRunId);
        assertAdapterAllowedForControlRun(context, adapterId);
        const routed = await executeAuthorizedControlEffect(context, () => context.kernel.applyDesktopIntentEffect(
          {
            ownerId,
            callerSessionId: context.callerSessionId,
            restrictiveCallerExecutionRole: context.executionRole,
            surfaceKind: parsed.originSurfaceKind,
            snapshotVersion: controlRouteSnapshotVersion(parsed.metadata),
            utterance: parsed.objective,
            effect: "spawn_agent",
            syntaxFacts: {
              parentRunId: parsed.parentRunId,
              requestedAgentCount: 1,
            },
          },
          () => context.kernel.delegateAgent({
            ...controlRunRecovery(context, adapterId),
            mode: "call",
            parentRunId: parsed.parentRunId,
            objective: parsed.objective,
            context: parsed.context,
            ownerId,
            requestId,
            adapterId,
            defaultAdapterId: adapterId,
            runMode: parsed.runMode,
            clientId: parsed.clientId,
            maxDepth: parsed.maxDepth,
            maxBudgetUsd: parsed.maxBudgetUsd,
            metadata: { ...(parsed.metadata ?? {}) },
            authoritySignal: context.executionLease?.signal,
          }),
        ));
        const result = routed.result;
        return stringifyToolResult({
          routeDecision: routed.decision,
          delegation: serializeDelegation(result.delegation),
          session: serializeSession(result.childSession),
          run: serializeRun(result.childRun),
          attempt: result.childAttempt ? serializeAttempt(result.childAttempt) : null,
          adapterSessionId: result.adapterSessionId ?? null,
          terminalStatus: result.terminalStatus ?? null,
          result: result.result
            ? {
                ...result.result,
                artifacts: result.result.artifacts.map(serializeArtifact),
              }
            : null,
        });
      }
      case "set_desktop_attention_override": {
        const parsed = agentControlToolSchemas.set_desktop_attention_override.parse(input);
        const ownerId = effectiveControlToolOwnerId(context, parsed.ownerId);
        const override = await executeAuthorizedControlEffect(context, () => context.kernel.setDesktopAttentionOverride({
          ownerId,
          subjectKind: parsed.subjectKind,
          subjectId: parsed.subjectId,
          dismissedAtMs: parsed.dismissed ? Date.now() : null,
          hiddenUntilMs: parsed.hiddenUntilMs ?? null,
          reason: parsed.reason ?? null,
        }));
        return stringifyToolResult({ override });
      }
    }
    } catch (error) {
      const rawCode = error && typeof error === "object" && "code" in error
        ? String((error as { code: unknown }).code)
        : "";
      const details = error instanceof PartialAgentSpawnError ? error.details : undefined;
      const isAuthorizedExternalSpawnAdmission = name === "spawn_agent"
        && context.authorizedCallerRunId !== undefined
        && context.authorizedProducerJournal !== undefined;
      const errorCode = error instanceof z.ZodError
        ? "invalid_tool_input"
        : /^[a-z0-9_]{1,64}$/.test(rawCode) ? rawCode : "control_tool_failed";
      return stringifyToolResult({
        error: {
          // Realtime callers consume this response through a model tool result,
          // so an admission failure needs a stable recovery signal rather than
          // an adapter/policy exception that may contain implementation detail.
          code: isAuthorizedExternalSpawnAdmission && errorCode === "control_tool_failed"
            ? "external_spawn_admission_failed"
            : errorCode,
          message: isAuthorizedExternalSpawnAdmission && errorCode === "control_tool_failed"
            ? "The requested agent could not be started. Try again."
            : error instanceof Error ? error.message : String(error),
          ...(isAuthorizedExternalSpawnAdmission ? { retryable: true } : {}),
          ...(details ? { details } : {}),
        },
      }, "failed");
    }
  });
}

function assertCanonicalRunId(value: string, fieldName: string): void {
  if (!value.startsWith("run_")) {
    throw new Error(
      `${fieldName} must be a canonical Intentive run_id starting with "run_"; omit it for a top-level background agent`,
    );
  }
}

function controlRouteSnapshotVersion(metadata: Record<string, unknown> | undefined): string {
  const value = metadata?.contextSnapshotVersion ?? metadata?.snapshotVersion;
  return typeof value === "string" && value.trim() ? value.trim() : "snapshot:control-unversioned";
}

function controlToolOwnerId(context: AgentControlToolContext): string {
  const ownerId = context.getOwnerId?.().trim();
  return ownerId || "desktop-local-user";
}


function effectiveControlToolOwnerId(context: AgentControlToolContext, requestedOwnerId?: string): string {
  const activeOwnerId = controlToolOwnerId(context);
  const ownerGuard = requestedOwnerId?.trim();
  if (requestedOwnerId !== undefined && !ownerGuard) {
    throw new Error("Requested ownerId cannot be empty");
  }
  if (ownerGuard && ownerGuard !== activeOwnerId) {
    throw new Error("Requested ownerId does not match the active control owner");
  }
  return activeOwnerId;
}

function rejectSynchronousNestedRun(context: AgentControlToolContext, adapterId: string, sessionId?: string): void {
  if (!context.kernel.isAdapterRegistered(adapterId)) {
    return;
  }
  if (
    (sessionId && context.kernel.hasActiveExecutionForSessionAdapter(sessionId, adapterId)) ||
    !context.kernel.hasExecutionCapacityForAdapter(adapterId)
  ) {
    throw new Error(
      `Synchronous ${adapterId} control-tool runs are unavailable while that adapter is already executing; use spawn mode or retry after the current run finishes.`,
    );
  }
}

const MAX_REALTIME_TOOL_RESULT_BYTES = 8 * 1024;
// Direct desktop control is authenticated local IPC, not a provider tool
// response. It still has a bounded payload so UI reconciliation cannot be held
// hostage by historical state, but it must not inherit the provider budget and
// lose structural roots such as the active owner.
const MAX_DIRECT_CONTROL_TOOL_RESULT_BYTES = 128 * 1024;

function isDirectControlOutput(context: AgentControlToolContext | undefined): boolean {
  return context?.trustedUserControl === true && context.callerSessionId === undefined;
}

function controlToolResultByteBudget(context: AgentControlToolContext | undefined): number {
  return isDirectControlOutput(context)
    ? MAX_DIRECT_CONTROL_TOOL_RESULT_BYTES
    : MAX_REALTIME_TOOL_RESULT_BYTES;
}

function controlToolResultProvenance(
  context: AgentControlToolContext | undefined,
  toolName: string,
): ToolResultEnvelope["provenance"] {
  const authorized = context?.authorizedToolInvocation;
  if (authorized) {
    // The capability tuple is the only identity a provider may observe. This
    // applies equally to validation, budget, and catch branches.
    return {
      invocationId: authorized.invocationId,
      runId: authorized.runId,
      attemptId: authorized.attemptId,
      toolName: authorized.toolName,
    };
  }
  return {
    invocationId: `control:${toolName}:${randomUUID()}`,
    runId: context?.authorizedCallerRunId ?? "unknown",
    attemptId: "unknown",
    toolName,
  };
}

/**
 * Provider-facing results carry one typed envelope.  The compact response is
 * useful in a realtime turn, while the full local result is recoverable by a
 * canonical artifact reference instead of being silently discarded.
 */
function withToolResultEnvelope(
  context: AgentControlToolContext,
  toolName: string,
  fullPayload: Record<string, unknown>,
  projectedPayload: Record<string, unknown>,
  ownerId: string,
  sessionId: string | undefined,
  existingFullOutputRef?: string,
  directProjectedPayload?: Record<string, unknown>,
): Record<string, unknown> {
  const byteBudget = controlToolResultByteBudget(context);
  const fullJson = JSON.stringify(fullPayload);
  const originalBytes = Buffer.byteLength(fullJson, "utf8");
  // A trusted desktop-control caller is a local UI/control-plane consumer, not
  // a model-visible realtime response. Preserve its typed schema whenever the
  // result fits the local bridge, and compact structurally (never into a JSON
  // string preview) only when it does not. This is the shared boundary used by
  // every coordinator action, including `get_agent_run`.
  const responsePayload = isDirectControlOutput(context)
    ? (directProjectedPayload ?? projectDirectControlPayload(fullPayload))
    : projectedPayload;
  const projectedBytes = Buffer.byteLength(JSON.stringify(responsePayload), "utf8");
  // Small structural projections are normal response shaping, not an
  // artifact-backed truncation. Once the full payload cannot cross the
  // provider boundary (or the caller supplied an existing canonical ref),
  // it must be recoverable or become a typed failure.
  const needsArtifactBackedProjection = originalBytes > projectedBytes
    && (existingFullOutputRef !== undefined || originalBytes > byteBudget);
  const fullOutputRef = needsArtifactBackedProjection
    ? existingFullOutputRef
      ?? (sessionId
      ? persistToolOutputArtifact(context, ownerId, sessionId, toolName, fullJson)
      : null)
    : null;
  if (needsArtifactBackedProjection && fullOutputRef === null) {
    // Never relabel a lossy success as an untruncated success. The provider
    // receives a typed failure unless the complete result is durably readable
    // through its artifact reference.
    return providerBudgetFailure(toolName, context);
  }
  const isRecoverableProjection = needsArtifactBackedProjection && fullOutputRef !== null;
  const result = {
    ...responsePayload,
    toolResultEnvelope: makeToolResultEnvelope({
      status: "succeeded",
      truncated: isRecoverableProjection,
      originalBytes: isRecoverableProjection ? originalBytes : projectedBytes,
      projectedBytes,
      fullOutputRef,
      provenance: controlToolResultProvenance(context, toolName),
    }),
  };
  if (Buffer.byteLength(JSON.stringify({ ok: true, ...result }), "utf8") > byteBudget) {
    const recoveredRef = fullOutputRef ?? (sessionId
      ? persistToolOutputArtifact(context, ownerId, sessionId, toolName, fullJson)
      : null);
    const failure = {
      error: {
        code: "tool_result_projection_exceeded_budget",
        message: `${toolName} output was saved locally; use its fullOutputRef with read_tool_output or search_tool_output.`,
      },
    };
    const failureBytes = Buffer.byteLength(JSON.stringify(failure), "utf8");
    if (recoveredRef) {
      return {
        ...failure,
        toolResultEnvelope: makeToolResultEnvelope({
          status: "failed",
          truncated: true,
          originalBytes: Math.max(originalBytes, projectedBytes),
          projectedBytes: failureBytes,
          fullOutputRef: recoveredRef,
          provenance: controlToolResultProvenance(context, toolName),
        }),
      };
    }
    return providerBudgetFailure(toolName, context);
  }
  return result;
}

function persistToolOutputArtifact(
  context: AgentControlToolContext,
  ownerId: string,
  sessionId: string,
  toolName: string,
  fullJson: string,
): string | null {
  try {
    const directory = join(defaultArtifactRoot(), "tool-output", ownerId, sessionId);
    mkdirSync(directory, { recursive: true });
    const path = join(directory, `${toolName}-${randomUUID()}.json`);
    writeFileSync(path, `${fullJson}\n`, "utf8");
    const artifact = context.kernel.persistArtifact({
      sessionId,
      kind: "tool_output",
      role: "tool_output",
      uri: pathToFileURL(path).toString(),
      displayName: `${toolName} full output`,
      mimeType: "application/json",
      contentHash: `sha256:${createHash("sha256").update(fullJson).digest("hex")}`,
      sizeBytes: Buffer.byteLength(fullJson, "utf8"),
      metadata: { toolName, projection: "provider_bounded", ownerId },
    });
    return `artifact:${artifact.artifactId}`;
  } catch {
    return null;
  }
}

function readToolOutputArtifact(context: AgentControlToolContext, artifactId: string, ownerId: string): AgentArtifact {
  const canonicalArtifactId = artifactId.startsWith("artifact:") ? artifactId.slice("artifact:".length) : artifactId;
  const artifact = context.kernel.inspectArtifacts({ artifactId: canonicalArtifactId, ownerId, limit: 1 })[0];
  if (!artifact || artifact.role !== "tool_output") {
    throw new Error("Tool output artifact was not found");
  }
  return artifact;
}

function readLocalArtifactText(uri: string): string {
  if (!uri.startsWith("file://")) throw new Error("Tool output artifact is not locally readable");
  return readFileSync(fileURLToPath(uri), "utf8");
}

function truncateUtf8(text: string, maxBytes: number): { text: string; truncated: boolean } {
  if (Buffer.byteLength(text, "utf8") <= maxBytes) return { text, truncated: false };
  let end = Math.min(text.length, maxBytes);
  while (end > 0 && Buffer.byteLength(text.slice(0, end), "utf8") > maxBytes) end -= 1;
  return { text: text.slice(0, end), truncated: true };
}

/**
 * The one and only provider-result finalizer for control tools. It owns both
 * normal and error output so malformed input, denied policy, and unexpected
 * throws cannot bypass the envelope/artifact contract.
 */
function stringifyToolResult(
  payload: Record<string, unknown>,
  requestedStatus?: "succeeded" | "failed" | "cancelled",
): string {
  const scope = controlToolOutputScope.getStore();
  const toolName = scope?.toolName ?? "unscoped_control_tool";
  // Realtime spawn results have a second, stricter compaction boundary in the
  // protocol relay (`compactRealtimeSpawnToolResult`).  Do not run the generic
  // provider projection first: accepted spawn payloads contain the durable
  // child run/session/attempt lifecycle under `agents[0]`, and that projection
  // can legitimately be hundreds of KB when the admitted context is large.
  // The relay compacts the full accepted result into the bounded canonical
  // child receipt before it reaches Swift or a provider. Typed/main-chat
  // callers keep the normal projection path below.
  if (
    toolName === "spawn_agent"
      && scope?.context.authorizedToolInvocation?.toolName === "spawn_agent"
      && scope?.context.authorizedProducerJournal
      && ["realtime", "realtime_voice"].includes(scope.context.authorizedProducerJournal.surface.surfaceKind)
      && Array.isArray(payload.agents)
      && payload.agents.length > 0
      && !Object.hasOwn(payload, "error")
      && payload.toolResultEnvelope === undefined
  ) {
    return stringifyRealtimeSpawnPrecompactResult(payload, requestedStatus, scope.context);
  }
  const existingEnvelope = payload.toolResultEnvelope;
  if (existingEnvelope) {
    // Dedicated detail tools have already persisted the complete source before
    // returning their compact projection. Preserve that reference verbatim.
    try {
      assertToolResultEnvelope(existingEnvelope);
      const sourceEnvelope = existingEnvelope;
      const status = requestedStatus ?? sourceEnvelope.status;
      const envelope = makeToolResultEnvelope({
        status,
        truncated: sourceEnvelope.truncated,
        originalBytes: sourceEnvelope.originalBytes,
        projectedBytes: sourceEnvelope.projectedBytes,
        fullOutputRef: sourceEnvelope.fullOutputRef,
        provenance: controlToolResultProvenance(scope?.context, toolName),
      });
      const result = JSON.stringify({ ok: status === "succeeded", ...payload, toolResultEnvelope: envelope });
      if (Buffer.byteLength(result, "utf8") <= controlToolResultByteBudget(scope?.context)) return result;
      return stringifyProviderBudgetFailure(toolName, envelope.originalBytes, envelope.fullOutputRef, scope?.context);
    } catch {
      // An invalid envelope is itself an untrusted transport value. Continue
      // through the finalizer below so it becomes a typed bounded failure.
    }
  }

  const fullJson = JSON.stringify(payload) ?? "{}";
  const originalBytes = Buffer.byteLength(fullJson, "utf8");
  const status = requestedStatus ?? (Object.hasOwn(payload, "error") ? "failed" : "succeeded");
  const ownerId = scope ? safeControlToolOwnerId(scope.context) : null;
  const sessionId = scope ? scope.context.callerSessionId ?? findSessionIdForToolOutput(payload) : undefined;
  let persistedFullOutputRef: string | null | undefined;
  const candidates = [
    payload,
    ...([[512, 24, 32], [256, 16, 24], [128, 10, 16], [64, 6, 10], [32, 3, 8]] as const)
      .map((limits) => compactProviderPayload(payload, ...limits)),
  ];
  for (const projectedPayload of candidates) {
    const projectedJson = JSON.stringify(projectedPayload) ?? "{}";
    const projectedBytes = Buffer.byteLength(projectedJson, "utf8");
    const projected = projectedBytes < originalBytes;
    if (projected && persistedFullOutputRef === undefined) {
      persistedFullOutputRef = ownerId && sessionId && scope
        ? persistToolOutputArtifact(scope.context, ownerId, sessionId, toolName, fullJson)
        : null;
    }
    const fullOutputRef = projected ? persistedFullOutputRef ?? null : null;
    if (projected && !fullOutputRef) {
      // Do not report a lossy success. The bounded error explicitly tells the
      // caller that no recoverable projection could be produced.
      return stringifyProviderBudgetFailure(toolName, undefined, null, scope?.context);
    }
    const toolResultEnvelope = makeToolResultEnvelope({
      status,
      truncated: projected,
      originalBytes: projected ? originalBytes : projectedBytes,
      projectedBytes,
      fullOutputRef,
      provenance: controlToolResultProvenance(scope?.context, toolName),
    });
    const result = JSON.stringify({
      ok: status === "succeeded",
      ...projectedPayload,
      toolResultEnvelope,
    });
    if (Buffer.byteLength(result, "utf8") <= controlToolResultByteBudget(scope?.context)) return result;
  }

  return stringifyProviderBudgetFailure(toolName, undefined, null, scope?.context);
}

/**
 * Preserve the complete accepted spawn shape until the realtime relay can
 * derive its compact semantic child receipt. This is intentionally scoped to
 * a kernel-authorized realtime producer; every other control-tool caller still
 * uses `stringifyToolResult`'s bounded projection/artifact behavior.
 */
function stringifyRealtimeSpawnPrecompactResult(
  payload: Record<string, unknown>,
  requestedStatus: "succeeded" | "failed" | "cancelled" | undefined,
  context: AgentControlToolContext,
): string {
  const fullJson = JSON.stringify(payload) ?? "{}";
  const bytes = Buffer.byteLength(fullJson, "utf8");
  const status = requestedStatus ?? (Object.hasOwn(payload, "error") ? "failed" : "succeeded");
  const ownerId = safeControlToolOwnerId(context);
  const fullOutputRef = ownerId && context.callerSessionId
    ? persistToolOutputArtifact(context, ownerId, context.callerSessionId, "spawn_agent", fullJson)
    : null;
  // The second compaction boundary removes the large run/context fields. Keep
  // the source envelope explicitly artifact-backed so the relay's finalizer
  // can preserve the complete control result while replacing its projection.
  // A missing artifact is not silently relabeled as an untruncated success.
  if (!fullOutputRef) {
    return stringifyProviderBudgetFailure("spawn_agent", bytes, null, context);
  }
  const envelope = makeToolResultEnvelope({
    status,
    truncated: true,
    originalBytes: bytes,
    projectedBytes: Math.min(Math.max(0, bytes - 1), MAX_REALTIME_TOOL_RESULT_BYTES),
    fullOutputRef,
    provenance: controlToolResultProvenance(context, "spawn_agent"),
  });
  return JSON.stringify({
    ok: status === "succeeded",
    ...payload,
    toolResultEnvelope: envelope,
  });
}

function stringifyProviderBudgetFailure(
  toolName: string,
  originalBytes?: number,
  fullOutputRef: string | null = null,
  context: AgentControlToolContext | undefined = controlToolOutputScope.getStore()?.context,
): string {
  const failure = {
    error: {
      code: "tool_result_exceeded_provider_budget",
      message: "The tool result exceeded the provider budget and was not delivered.",
    },
  };
  const projectedBytes = Buffer.byteLength(JSON.stringify(failure), "utf8");
  const truncated = fullOutputRef !== null && (originalBytes ?? projectedBytes) > projectedBytes;
  return JSON.stringify({
    ok: false,
    ...failure,
    toolResultEnvelope: makeToolResultEnvelope({
      status: "failed",
      truncated,
      originalBytes: truncated ? originalBytes! : projectedBytes,
      projectedBytes,
      fullOutputRef: truncated ? fullOutputRef : null,
      provenance: controlToolResultProvenance(context, toolName),
    }),
  });
}

function safeControlToolOwnerId(context: AgentControlToolContext): string | null {
  try {
    return controlToolOwnerId(context);
  } catch {
    return null;
  }
}

function findSessionIdForToolOutput(value: unknown, depth = 0): string | undefined {
  if (depth > 6 || !value || typeof value !== "object") return undefined;
  if (Array.isArray(value)) {
    for (const item of value.slice(0, 64)) {
      const sessionId = findSessionIdForToolOutput(item, depth + 1);
      if (sessionId) return sessionId;
    }
    return undefined;
  }
  const record = value as Record<string, unknown>;
  if (typeof record.sessionId === "string" && record.sessionId.startsWith("ses_")) return record.sessionId;
  for (const key of ["session", "sessions", "run", "runs", "snapshot", "route", "dispatch", "result"]) {
    const sessionId = findSessionIdForToolOutput(record[key], depth + 1);
    if (sessionId) return sessionId;
  }
  return undefined;
}

/**
 * Last-resort transport guard for every control-tool branch. Operations with a
 * recoverable full result use `withToolResultEnvelope`; this path makes an
 * unexpected oversize response a typed failure instead of a provider-specific
 * disconnect or an unbounded JSONL frame.
 */
function providerBudgetFailure(
  toolName: string,
  context: AgentControlToolContext | undefined = controlToolOutputScope.getStore()?.context,
): Record<string, unknown> {
  const failure = {
    error: {
      code: "tool_result_exceeded_provider_budget",
      message: "The tool result exceeded the provider budget and was not delivered.",
    },
  };
  const bytes = Buffer.byteLength(JSON.stringify(failure), "utf8");
  return {
    ...failure,
    toolResultEnvelope: makeToolResultEnvelope({
      status: "failed",
      truncated: false,
      originalBytes: bytes,
      projectedBytes: bytes,
      fullOutputRef: null,
      provenance: controlToolResultProvenance(context, toolName),
    }),
  };
}

/** A compact projection for detail endpoints whose stored JSON can be huge. */
function projectProviderPayload(fullPayload: Record<string, unknown>, toolName: string): Record<string, unknown> {
  const originalBytes = Buffer.byteLength(JSON.stringify(fullPayload), "utf8");
  const maximumProjectedBytes = 5 * 1024;
  const projectionLimits = [
    [512, 24, 32],
    [256, 16, 24],
    [128, 10, 16],
    [64, 6, 10],
    [48, 4, 8],
  ] as const;
  for (const limits of projectionLimits) {
    const compact = compactProviderPayload(fullPayload, ...limits);
    if (Buffer.byteLength(JSON.stringify(compact), "utf8") <= maximumProjectedBytes) return compact;
  }
  const preview = truncateUtf8(JSON.stringify(compactProviderPayload(fullPayload, 64, 6, 10)), maximumProjectedBytes).text;
  return {
    projection: "bounded_json_preview",
    toolName,
    originalBytes,
    preview,
  };
}

/**
 * Desktop automation and the Swift coordinator parse these values as JSON.
 * Their contract must remain structurally usable even when one historical run
 * contains a large stored context or event ledger. Keep a small reserve for
 * the typed envelope and artifact reference, then progressively compact the
 * same object shape rather than returning a provider-only string preview.
 */
function projectDirectControlPayload(fullPayload: Record<string, unknown>): Record<string, unknown> {
  const maximumProjectedBytes = MAX_DIRECT_CONTROL_TOOL_RESULT_BYTES - 8 * 1024;
  if (Buffer.byteLength(JSON.stringify(fullPayload), "utf8") <= maximumProjectedBytes) return fullPayload;
  for (const limits of [[4096, 200, 128], [2048, 128, 96], [1024, 64, 64], [512, 32, 40]] as const) {
    const compact = compactProviderPayload(fullPayload, ...limits);
    if (Buffer.byteLength(JSON.stringify(compact), "utf8") <= maximumProjectedBytes) return compact;
  }
  return compactProviderPayload(fullPayload, 256, 16, 24);
}

const OMITTED_PROVIDER_VALUE = Symbol("omitted_provider_value");

/**
 * Central defensive projection for model-visible control results. Dedicated
 * operations retain a full artifact reference; this fallback keeps unrelated
 * control responses structurally useful and under the transport ceiling.
 */
function compactProviderPayload(
  payload: Record<string, unknown>,
  stringLimit = 512,
  arrayLimit = 24,
  fieldLimit = 32,
): Record<string, unknown> {
  return compactProviderValue(payload, "", 0, stringLimit, arrayLimit, fieldLimit) as Record<string, unknown>;
}

function compactProviderValue(
  value: unknown,
  key: string,
  depth: number,
  stringLimit: number,
  arrayLimit: number,
  fieldLimit: number,
): unknown {
  const lowerKey = key.toLocaleLowerCase();
  if (lowerKey.includes("surfacecontext") || lowerKey.includes("admittedcontext") || lowerKey === "renderedcontext") {
    return OMITTED_PROVIDER_VALUE;
  }
  if (typeof value === "string") {
    return truncateUtf8(value, stringLimit).text;
  }
  if (Array.isArray(value)) {
    const retained = value.length <= arrayLimit
      ? value
      : [...value.slice(0, Math.min(3, arrayLimit)), ...value.slice(-(arrayLimit - Math.min(3, arrayLimit)))];
    const items = retained
      .map((item) => compactProviderValue(item, "", depth + 1, stringLimit, arrayLimit, fieldLimit))
      .filter((item) => item !== OMITTED_PROVIDER_VALUE);
    if (value.length > items.length) items.push({ truncatedItemCount: value.length - items.length });
    return items;
  }
  if (!value || typeof value !== "object") return value;
  if (depth >= 5) return { projection: "depth_limited" };
  const actualFieldLimit = depth == 0 ? Math.max(fieldLimit, 64) : fieldLimit;
  const entries = Object.entries(value as Record<string, unknown>).slice(0, actualFieldLimit);
  const compact: Record<string, unknown> = {};
  for (const [childKey, childValue] of entries) {
    const projected = compactProviderValue(childValue, childKey, depth + 1, stringLimit, arrayLimit, fieldLimit);
    if (projected !== OMITTED_PROVIDER_VALUE) compact[childKey] = projected;
  }
  if (Object.keys(value as Record<string, unknown>).length > entries.length) {
    compact.truncatedFieldCount = Object.keys(value as Record<string, unknown>).length - entries.length;
  }
  return compact;
}

function serializeAgentSessionsList(
  sessions: Parameters<typeof serializeSessionSummary>[0][],
  overrides: {
    subjectKind: string;
    subjectId: string;
    dismissedAtMs?: number | null;
    hiddenUntilMs?: number | null;
  }[],
): Record<string, unknown> {
  // This result is used directly as a realtime provider tool response. Keep
  // the canonical list well below the provider's aggregate-turn budget so a
  // routine status lookup cannot prevent the provider from speaking the
  // completed child result it just found.
  // Reserve room for the common ToolResultEnvelope. The final guard above is
  // authoritative and protects every provider response from transport drift.
  const maximumSerializedBytes = 6 * 1024;
  const dismissed = new Set(
    overrides
      .filter((override) => override.dismissedAtMs != null || (override.hiddenUntilMs ?? 0) > Date.now())
      .map((override) => `${override.subjectKind}:${override.subjectId}`),
  );
  // Keep the canonical list operation compact. A session's persisted run input
  // can include hundreds of kilobytes of surface context, and returning that
  // here used to make a routine realtime `list_agent_sessions` response exceed
  // provider WebSocket limits. Full run/session detail remains available from
  // `get_agent_run` and the internal awareness snapshot.
  const serializedSessions: Record<string, unknown>[] = [];
  const floatingAgentPills: Record<string, unknown>[] = [];
  let truncated = false;

  for (const summary of sessions) {
    const serializedSession = serializeSessionListSummary(summary);
    const run = summary.activeRun ?? summary.latestRun;
    const runId = run?.runId ?? null;
    const sessionId = summary.session.sessionId;
    const surfaceKind = summary.session.surfaceKind;
    const floatingPill = (
      (surfaceKind === "floating_bar" || surfaceKind === "background_agent" || surfaceKind === "floating_pill")
      && !(runId && dismissed.has(`run:${runId}`))
      && !dismissed.has(`session:${sessionId}`)
    ) ? serializeFloatingPillSnapshot(summary) : null;

    serializedSessions.push(serializedSession);
    if (floatingPill) floatingAgentPills.push(floatingPill);
    const candidate = {
      sessions: serializedSessions,
      floating_agent_pills: floatingAgentPills,
      truncated: false,
      fetched_session_count: sessions.length,
    };
    if (Buffer.byteLength(JSON.stringify({ ok: true, ...candidate }), "utf8") > maximumSerializedBytes) {
      serializedSessions.pop();
      if (floatingPill) floatingAgentPills.pop();
      truncated = true;
      break;
    }
  }

  return {
    sessions: serializedSessions,
    floating_agent_pills: floatingAgentPills,
    truncated,
    returned_session_count: serializedSessions.length,
    fetched_session_count: sessions.length,
  };
}

function serializeFullSessionListing(
  sessions: Parameters<typeof serializeSessionSummary>[0][],
  projected: Record<string, unknown>,
): Record<string, unknown> {
  return {
    ...projected,
    canonicalSessions: sessions.map((summary) => ({
      session: summary.session,
      latestRun: summary.latestRun ?? null,
      activeRun: summary.activeRun ?? null,
      adapterBindings: summary.adapterBindings,
    })),
  };
}

const CONTROL_LIST_TEXT_LIMIT = 512;
const CONTROL_LIST_BINDING_LIMIT = 4;

function boundedControlListText(value: unknown, limit = CONTROL_LIST_TEXT_LIMIT): string | null {
  if (typeof value !== "string" || value.length === 0) return null;
  return value.length <= limit ? value : `${value.slice(0, limit)}\n[truncated]`;
}

function serializeSessionListSummary(summary: {
  session: AgentSession;
  latestRun?: AgentRun;
  activeRun?: AgentRun;
  adapterBindings: AdapterBinding[];
}): Record<string, unknown> {
  const session = summary.session;
  return {
    session: {
      sessionId: session.sessionId,
      ownerId: session.ownerId,
      title: boundedControlListText(session.title, 160),
      status: session.status,
      surfaceKind: session.surfaceKind,
      executionRole: session.executionRole,
      externalRefKind: session.externalRefKind,
      externalRefId: session.externalRefId,
      defaultAdapterId: session.defaultAdapterId,
      modelProfile: session.modelProfile,
      createdAtMs: session.createdAtMs,
      updatedAtMs: session.updatedAtMs,
      lastActivityAtMs: session.lastActivityAtMs,
    },
    latestRun: summary.latestRun ? serializeRunListSummary(summary.latestRun) : null,
    activeRun: summary.activeRun ? serializeRunListSummary(summary.activeRun) : null,
    // Binding history grows as a long-lived session is refreshed. It is not a
    // second source of agent identity, so never let it evict the session/run
    // roots from a bounded status response.
    adapterBindings: summary.adapterBindings.slice(0, CONTROL_LIST_BINDING_LIMIT).map((binding) => ({
      bindingId: binding.bindingId,
      sessionId: binding.sessionId,
      adapterId: binding.adapterId,
      adapterNativeSessionId: binding.adapterNativeSessionId,
      resumeFidelity: binding.resumeFidelity,
      status: binding.status,
      modelId: binding.modelId,
      updatedAtMs: binding.updatedAtMs,
    })),
    adapterBindingsTruncated: summary.adapterBindings.length > CONTROL_LIST_BINDING_LIMIT,
  };
}

function serializeRunListSummary(run: AgentRun): Record<string, unknown> {
  const input = parseJsonObject(run.inputJson) as Record<string, unknown>;
  return appendErrorFields(
    {
      runId: run.runId,
      sessionId: run.sessionId,
      parentRunId: run.parentRunId,
      status: run.status,
      mode: run.mode,
      input: {
        prompt: boundedControlListText(input.prompt),
      },
      requestedModelId: run.requestedModelId,
      finalText: boundedControlListText(run.finalText),
      createdAtMs: run.createdAtMs,
      startedAtMs: run.startedAtMs,
      completedAtMs: run.completedAtMs,
      updatedAtMs: run.updatedAtMs,
    },
    run.errorCode,
    boundedControlListText(run.errorMessage),
  );
}

function serializeDirectControlRunSummary(run: AgentRun): Record<string, unknown> {
  const input = parseJsonObject(run.inputJson) as Record<string, unknown>;
  const metadata = input.metadata;
  const externalSurface = metadata && typeof metadata === "object" && !Array.isArray(metadata)
    ? (metadata as Record<string, unknown>).externalSurface
    : undefined;
  const externalAuthority = externalSurface && typeof externalSurface === "object" && !Array.isArray(externalSurface)
    ? boundedControlListText((externalSurface as Record<string, unknown>).authority, 96)
    : null;
  const summary = serializeRunListSummary(run);
  if (!externalAuthority) return summary;
  const inputSummary = summary.input as Record<string, unknown>;
  return {
    ...summary,
    input: {
      ...inputSummary,
      metadata: {
        externalSurface: {
          authority: externalAuthority,
        },
      },
    },
  };
}

function serializeFloatingPillSnapshot(summary: {
  session: AgentSession;
  latestRun?: AgentRun;
  activeRun?: AgentRun;
}): Record<string, unknown> {
  const session = summary.session;
  const run = summary.activeRun ?? summary.latestRun;
  const input = (run ? parseJsonObject(run.inputJson) : {}) as Record<string, unknown>;
  const metadata = parseJsonObject(session.metadataJson) as Record<string, unknown>;
  const runId = run?.runId ?? null;
  const sessionId = session.sessionId || null;
  const errorMessage = run?.errorMessage || null;
  const errorCode = run?.errorCode || null;
  const pillId =
    session.externalRefId ||
    (typeof metadata.pillId === "string" ? metadata.pillId : null) ||
    runId ||
    sessionId;
  return {
    id: pillId,
    runId,
    sessionId,
    title: boundedControlListText(session.title, 160) ?? "Background agent",
    status: run?.status ?? session.status,
    latestActivity: boundedControlListText(run?.finalText ?? errorMessage ?? input.prompt ?? session.title ?? "") ?? "",
    query: boundedControlListText(input.prompt) ?? "",
    createdAtMs: session.createdAtMs ?? null,
    completedAtMs: run?.completedAtMs ?? null,
    errorCode: boundedControlListText(errorCode, 128),
    errorMessage: boundedControlListText(errorMessage),
  };
}

function serializeSessionSummary(summary: {
  session: AgentSession;
  latestRun?: AgentRun;
  activeRun?: AgentRun;
  adapterBindings: AdapterBinding[];
}): Record<string, unknown> {
  return {
    session: serializeSession(summary.session),
    latestRun: summary.latestRun ? serializeRun(summary.latestRun) : null,
    activeRun: summary.activeRun ? serializeRun(summary.activeRun) : null,
    adapterBindings: summary.adapterBindings.map(serializeBinding),
  };
}

function serializeRunDetails(details: {
  session: AgentSession;
  run: AgentRun;
  attempts: RunAttempt[];
  adapterBindings: AdapterBinding[];
  artifacts: AgentArtifact[];
  events: AgentEvent[];
  parentDelegations: AgentDelegation[];
  childDelegations: AgentDelegation[];
  toolInvocations: Array<{
    invocationId: string;
    runId: string;
    attemptId: string;
    toolName: string;
    status: string;
    errorCode: string | null;
    preparedAtMs: number;
    dispatchedAtMs: number | null;
    completedAtMs: number | null;
    updatedAtMs: number;
  }>;
}): Record<string, unknown> {
  return {
    session: serializeSession(details.session),
    run: serializeRun(details.run),
    attempts: details.attempts.map(serializeAttempt),
    adapterBindings: details.adapterBindings.map(serializeBinding),
    artifacts: details.artifacts.map(serializeArtifact),
    events: details.events.map(serializeEvent),
    parentDelegations: details.parentDelegations.map(serializeDelegation),
    childDelegations: details.childDelegations.map(serializeDelegation),
    toolInvocations: details.toolInvocations,
  };
}

function serializeAwarenessSnapshot(snapshot: DesktopAwarenessSnapshot): Record<string, unknown> {
  return {
    ownerId: snapshot.ownerId,
    generatedAtMs: snapshot.generatedAtMs,
    sessions: snapshot.sessions.map(serializeSessionSummary),
    runs: snapshot.runs.map(serializeRun),
    dispatches: snapshot.dispatches,
    artifactDeliveries: snapshot.artifactDeliveries,
    memoryCandidates: snapshot.memoryCandidates,
    actionQueue: snapshot.actionQueue,
    runtime: snapshot.runtime,
  };
}

/**
 * Direct UI reconciliation needs the canonical owner/session/run identity, not
 * every historical run input. Reuse the safe status-list fields, preserve
 * newest-first ordering, and leave the complete snapshot recoverable through
 * the envelope when it is larger than this local bridge view.
 */
function projectDirectControlAwarenessSnapshot(snapshot: DesktopAwarenessSnapshot): Record<string, unknown> {
  const sessionListing = serializeAgentSessionsList(snapshot.sessions, []);
  const sessions = Array.isArray(sessionListing.sessions) ? sessionListing.sessions : [];
  const runs = snapshot.runs.slice(0, 50).map(serializeDirectControlRunSummary);
  return {
    snapshot: {
      ownerId: snapshot.ownerId,
      generatedAtMs: snapshot.generatedAtMs,
      sessions,
      runs,
      runtime: snapshot.runtime,
      sessionCount: snapshot.sessions.length,
      runCount: snapshot.runs.length,
      sessionsTruncated: sessionListing.truncated === true,
      runsTruncated: snapshot.runs.length > runs.length,
    },
  };
}

function serializeSession(session: AgentSession): Record<string, unknown> {
  return {
    sessionId: session.sessionId,
    ownerId: session.ownerId,
    agentDefinitionId: session.agentDefinitionId,
    title: session.title,
    status: session.status,
    surfaceKind: session.surfaceKind,
    executionRole: session.executionRole,
    providerBoundary: session.providerBoundary,
    externalRefKind: session.externalRefKind,
    externalRefId: session.externalRefId,
    defaultAdapterId: session.defaultAdapterId,
    defaultCwd: session.defaultCwd,
    modelProfile: session.modelProfile,
    metadata: parseJsonObject(session.metadataJson),
    createdAtMs: session.createdAtMs,
    updatedAtMs: session.updatedAtMs,
    lastActivityAtMs: session.lastActivityAtMs,
  };
}

function appendErrorFields(
  payload: Record<string, unknown>,
  errorCode: string | null | undefined,
  errorMessage: string | null | undefined,
): Record<string, unknown> {
  if (errorCode != null && errorCode !== "") {
    payload.errorCode = errorCode;
  }
  if (errorMessage != null && errorMessage !== "") {
    payload.errorMessage = errorMessage;
  }
  return payload;
}

function serializeRun(run: AgentRun): Record<string, unknown> {
  return appendErrorFields(
    {
      runId: run.runId,
      sessionId: run.sessionId,
      parentRunId: run.parentRunId,
      clientId: run.clientId,
      requestId: run.requestId,
      idempotencyKey: run.idempotencyKey,
      status: run.status,
      mode: run.mode,
      input: parseJsonObject(run.inputJson),
      requestedModelId: run.requestedModelId,
      cwd: run.cwd,
      finalText: run.finalText,
      result: parseOptionalJsonObject(run.resultJson),
      usage: {
        inputTokens: run.inputTokens,
        outputTokens: run.outputTokens,
        cacheReadTokens: run.cacheReadTokens,
        cacheWriteTokens: run.cacheWriteTokens,
        costUsd: run.costUsd,
      },
      createdAtMs: run.createdAtMs,
      startedAtMs: run.startedAtMs,
      completedAtMs: run.completedAtMs,
      updatedAtMs: run.updatedAtMs,
    },
    run.errorCode,
    run.errorMessage,
  );
}

function serializeAttempt(attempt: RunAttempt): Record<string, unknown> {
  return appendErrorFields(
    {
      attemptId: attempt.attemptId,
      runId: attempt.runId,
      attemptNo: attempt.attemptNo,
      status: attempt.status,
      adapterId: attempt.adapterId,
      runtimeNodeId: attempt.runtimeNodeId,
      bindingId: attempt.bindingId,
      adapterNativeRunId: attempt.adapterNativeRunId,
      resumeFromAttemptId: attempt.resumeFromAttemptId,
      checkpointArtifactId: attempt.checkpointArtifactId,
      retryReason: attempt.retryReason,
      retryable: attempt.retryable === 1,
      cancellationRequestedAtMs: attempt.cancellationRequestedAtMs,
      cancellationDispatchedAtMs: attempt.cancellationDispatchedAtMs,
      cancellationAcknowledgedAtMs: attempt.cancellationAcknowledgedAtMs,
      metadata: parseJsonObject(attempt.metadataJson),
      createdAtMs: attempt.createdAtMs,
      startedAtMs: attempt.startedAtMs,
      completedAtMs: attempt.completedAtMs,
      updatedAtMs: attempt.updatedAtMs,
    },
    attempt.errorCode,
    attempt.errorMessage,
  );
}

function serializeBinding(binding: AdapterBinding): Record<string, unknown> {
  return {
    bindingId: binding.bindingId,
    sessionId: binding.sessionId,
    adapterId: binding.adapterId,
    bindingGeneration: binding.bindingGeneration,
    adapterNativeSessionId: binding.adapterNativeSessionId,
    adapterInstanceId: binding.adapterInstanceId,
    resumeFidelity: binding.resumeFidelity,
    status: binding.status,
    cwd: binding.cwd,
    modelId: binding.modelId,
    metadata: parseJsonObject(binding.metadataJson),
    createdAtMs: binding.createdAtMs,
    updatedAtMs: binding.updatedAtMs,
    lastUsedAtMs: binding.lastUsedAtMs,
    invalidatedAtMs: binding.invalidatedAtMs,
  };
}

function serializeEvent(event: AgentEvent): Record<string, unknown> {
  return {
    eventSeq: event.eventSeq,
    eventId: event.eventId,
    sessionId: event.sessionId,
    runId: event.runId,
    attemptId: event.attemptId,
    type: event.type,
    retentionClass: event.retentionClass,
    visibility: event.visibility,
    payload: parseJsonObject(event.payloadJson),
    createdAtMs: event.createdAtMs,
  };
}

function serializeDelegation(delegation: AgentDelegation): Record<string, unknown> {
  return {
    delegationId: delegation.delegationId,
    parentSessionId: delegation.parentSessionId,
    parentRunId: delegation.parentRunId,
    childSessionId: delegation.childSessionId,
    childRunId: delegation.childRunId,
    mode: delegation.mode,
    status: delegation.status,
    objective: delegation.objective,
    request: parseJsonObject(delegation.requestJson),
    resultArtifactId: delegation.resultArtifactId,
    createdAtMs: delegation.createdAtMs,
    completedAtMs: delegation.completedAtMs,
  };
}

function parseOptionalJsonObject(value: string | null): unknown {
  return value === null ? null : parseJsonObject(value);
}

function parseJsonObject(value: string): unknown {
  try {
    return JSON.parse(value);
  } catch {
    return { raw: value };
  }
}
