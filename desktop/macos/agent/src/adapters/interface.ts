import type { OutboundMessageDraft } from "../protocol.js";
import type { RuntimeFailure } from "../runtime/failures.js";
import type { ArtifactRole, ResumeFidelity, RunMode } from "../runtime/types.js";

export interface HarnessConfig {
  omiApiBaseUrl?: string;
  authToken?: string;
}

export interface SessionOpts {
  cwd: string;
  systemPrompt?: string;
  executionRole?: "coordinator" | "leaf";
}

export interface WarmupSessionConfig {
  key: string;
  systemPrompt?: string;
}

export interface PromptResult {
  text: string;
  sessionId: string;
  costUsd?: number;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
}

export type PromptBlock =
  | { type: "text"; text: string }
  | { type: "image"; data: string; mimeType: string };

export interface ToolDef {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

export type ToolExecutor = (name: string, input: Record<string, unknown>) => Promise<string>;
export type EventCallback = (event: OutboundMessageDraft) => void;

export enum HarnessFeature {
  BIDIRECTIONAL_RPC = "bidirectional_rpc",
  SESSION_RESUME = "session_resume",
  COST_TRACKING = "cost_tracking",
}

export interface HarnessAdapter {
  readonly name: string;
  start(): Promise<void>;
  stop(): Promise<void>;
  createSession(opts: SessionOpts): Promise<string>;
  sendPrompt(
    sessionId: string,
    prompt: PromptBlock[],
    tools: ToolDef[],
    mode: "ask" | "act",
    onEvent: EventCallback,
    onToolCall: ToolExecutor,
    signal?: AbortSignal,
  ): Promise<PromptResult>;
  abort(sessionId: string): void;
  warmup?(cwd: string, sessions: WarmupSessionConfig[]): Promise<void>;
  invalidateSession?(sessionKey: string): void;
  supportsFeature(feature: HarnessFeature): boolean;
}

export interface AdapterCapabilities {
  readonly resumeFidelity: ResumeFidelity;
  readonly supportsNativeResume: boolean;
  readonly supportsCancellation: boolean;
  readonly acknowledgesCancellation: boolean;
  readonly requiresPinnedWorker: boolean;
  readonly supportsArtifactEmission: boolean;
  readonly supportsTools: boolean;
  readonly restartBehavior: "native_bindings_survive" | "process_local_bindings_stale" | "attempts_orphaned";
}

export type AdapterCredentialScope = "managed_cloud" | "local_user";
export type ProductionAdapterId = "pi-mono";
export const PRODUCTION_ADAPTER_IDS = ["pi-mono"] as const satisfies readonly ProductionAdapterId[];

export function isProductionAdapterId(adapterId: string): adapterId is ProductionAdapterId {
  return adapterId === "pi-mono";
}

export function adapterCapabilitiesFor(_adapterId: ProductionAdapterId): AdapterCapabilities {
  return {
    resumeFidelity: "none",
    supportsNativeResume: false,
    supportsCancellation: true,
    acknowledgesCancellation: false,
    requiresPinnedWorker: true,
    supportsArtifactEmission: false,
    supportsTools: true,
    restartBehavior: "process_local_bindings_stale",
  };
}

export function adapterCredentialScopeFor(_adapterId: ProductionAdapterId): AdapterCredentialScope {
  return "managed_cloud";
}

export interface OpenBindingInput {
  sessionId: string;
  cwd: string;
  model?: string;
  systemPrompt?: string;
  metadata?: Record<string, unknown>;
}

export interface ResumeBindingInput extends OpenBindingInput {
  adapterNativeSessionId: string;
}

export interface AdapterBindingHandle {
  bindingId?: string;
  sessionId: string;
  adapterId: string;
  adapterNativeSessionId: string;
  resumeFidelity: ResumeFidelity;
  cwd: string;
  model?: string;
  metadata?: Record<string, unknown>;
}

export type OpenedBinding = AdapterBindingHandle;

export interface AdapterAttemptContext {
  sessionId: string;
  ownerId: string;
  requestId: string;
  clientId: string;
  runId: string;
  attemptId: string;
  toolCapabilityRef: string;
  binding: AdapterBindingHandle;
  prompt: PromptBlock[];
  mode: RunMode;
  model?: string;
  tools?: ToolDef[];
  metadata?: Record<string, unknown>;
}

export type AdapterEventSink = (event: OutboundMessageDraft) => void;

export interface AdapterArtifactReference {
  kind: string;
  role: ArtifactRole;
  uri: string;
  displayName?: string | null;
  mimeType?: string | null;
  contentHash?: string | null;
  sizeBytes?: number | null;
  metadata?: Record<string, unknown>;
}

export interface AdapterAttemptResult {
  text: string;
  costUsd?: number;
  inputTokens?: number;
  outputTokens?: number;
  cacheReadTokens?: number;
  cacheWriteTokens?: number;
  adapterSessionId: string;
  terminalStatus: "succeeded" | "failed" | "cancelled";
  failure?: RuntimeFailure;
  artifacts?: AdapterArtifactReference[];
}

export interface CancelAttemptContext {
  sessionId: string;
  ownerId?: string;
  requestId?: string;
  clientId?: string;
  runId?: string;
  attemptId?: string;
  binding?: AdapterBindingHandle;
}

export interface CancelDispatchResult {
  accepted: boolean;
  dispatchAttempted: boolean;
  adapterAcknowledged: boolean;
  message?: string;
}

export interface RuntimeAdapter {
  readonly adapterId: string;
  readonly capabilities: AdapterCapabilities;
  start(): Promise<void>;
  stop(): Promise<void>;
  openBinding(input: OpenBindingInput): Promise<OpenedBinding>;
  resumeBinding(input: ResumeBindingInput): Promise<OpenedBinding>;
  executeAttempt(
    context: AdapterAttemptContext,
    sink: AdapterEventSink,
    signal: AbortSignal,
  ): Promise<AdapterAttemptResult>;
  cancelAttempt(context: CancelAttemptContext): Promise<CancelDispatchResult>;
  closeBinding?(binding: AdapterBindingHandle): Promise<void>;
}

export function assertAdapterBindingContract(binding: AdapterBindingHandle, operation: string): void {
  if (!binding.adapterNativeSessionId) {
    throw new Error(`${operation} returned an empty adapterNativeSessionId`);
  }
  if (binding.adapterNativeSessionId === binding.sessionId) {
    throw new Error(`${operation} conflated Omi sessionId ${binding.sessionId} with adapterNativeSessionId`);
  }
}

export function assertAdapterAttemptResultContract(
  context: AdapterAttemptContext,
  result: AdapterAttemptResult,
  operation: string,
): void {
  if (!result.adapterSessionId) {
    throw new Error(`${operation} returned an empty adapterSessionId`);
  }
  if (result.adapterSessionId === context.sessionId) {
    throw new Error(`${operation} conflated Omi sessionId ${context.sessionId} with adapter native session id`);
  }
  if (result.adapterSessionId !== context.binding.adapterNativeSessionId) {
    throw new Error(`${operation} returned adapterSessionId ${result.adapterSessionId} for binding ${context.binding.adapterNativeSessionId}`);
  }
}
