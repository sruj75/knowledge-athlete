import { generateAgentId } from "./sqlite-store.js";
import type { AgentExecutionRole, AgentStore, ProviderBoundary } from "./types.js";

export interface SurfaceRef {
  surfaceKind: string;
  externalRefKind: string;
  externalRefId: string;
}

export interface ResolveSurfaceSessionInput {
  ownerId: string;
  surfaceRef: SurfaceRef;
  defaultAdapterId?: string;
  executionRole?: AgentExecutionRole;
  providerBoundary?: ProviderBoundary;
  modelProfile?: string | null;
  defaultCwd?: string | null;
  executionProfileSource?: "creation" | "child_derivation";
  title?: string | null;
}

export interface ResolveSurfaceSessionResult {
  conversationId: string;
  agentSessionId: string;
}

const SHARED_CHAT_SURFACES = new Set(["main_chat", "floating_chat", "realtime_voice", "realtime"]);

function sharesChatContinuity(surfaceRef: SurfaceRef): boolean {
  return surfaceRef.externalRefKind === "chat" && SHARED_CHAT_SURFACES.has(surfaceRef.surfaceKind);
}

export function surfaceRefKey(surfaceRef: SurfaceRef): string {
  return `${surfaceRef.surfaceKind}|${surfaceRef.externalRefKind}|${surfaceRef.externalRefId}`;
}

function isSqliteUniqueConstraintError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return (
    error.message.includes("UNIQUE constraint failed") ||
    error.message.includes("SQLITE_CONSTRAINT_UNIQUE")
  );
}

function readSurfaceConversation(
  store: AgentStore,
  input: ResolveSurfaceSessionInput,
): ResolveSurfaceSessionResult | undefined {
  const row = store.getOptionalRow(
    `SELECT conversation_id, agent_session_id
     FROM surface_conversations
     WHERE owner_id = ? AND surface_kind = ? AND external_ref_kind = ? AND external_ref_id = ?`,
    [
      input.ownerId,
      input.surfaceRef.surfaceKind,
      input.surfaceRef.externalRefKind,
      input.surfaceRef.externalRefId,
    ],
  );
  if (!row) return undefined;
  return {
    conversationId: String(row.conversation_id),
    agentSessionId: String(row.agent_session_id),
  };
}

function readSessionIdByExternalRef(store: AgentStore, input: ResolveSurfaceSessionInput): string | undefined {
  const row = store.getOptionalRow(
    `SELECT session_id FROM sessions
     WHERE owner_id = ? AND external_ref_kind = ? AND external_ref_id = ?`,
    [input.ownerId, input.surfaceRef.externalRefKind, input.surfaceRef.externalRefId],
  );
  return row ? String(row.session_id) : undefined;
}

function readSharedChatMapping(
  store: AgentStore,
  input: ResolveSurfaceSessionInput,
): ResolveSurfaceSessionResult | undefined {
  if (!sharesChatContinuity(input.surfaceRef)) return undefined;
  const row = store.getOptionalRow(
    `SELECT conversation_id, agent_session_id
     FROM surface_conversations
     WHERE owner_id = ? AND external_ref_kind = ? AND external_ref_id = ?
       AND surface_kind IN ('main_chat', 'floating_chat', 'realtime_voice', 'realtime')
     ORDER BY CASE surface_kind
       WHEN 'main_chat' THEN 0
       WHEN 'floating_chat' THEN 1
       WHEN 'realtime_voice' THEN 2
       ELSE 3 END,
       created_at_ms ASC
     LIMIT 1`,
    [input.ownerId, input.surfaceRef.externalRefKind, input.surfaceRef.externalRefId],
  );
  return row ? {
    conversationId: String(row.conversation_id),
    agentSessionId: String(row.agent_session_id),
  } : undefined;
}

function touchSurfaceConversation(store: AgentStore, input: ResolveSurfaceSessionInput, now: number): void {
  store.execute(
    `UPDATE surface_conversations
     SET last_active_at_ms = ?
     WHERE owner_id = ? AND surface_kind = ? AND external_ref_kind = ? AND external_ref_id = ?`,
    [
      now,
      input.ownerId,
      input.surfaceRef.surfaceKind,
      input.surfaceRef.externalRefKind,
      input.surfaceRef.externalRefId,
    ],
  );
}

function createSurfaceConversationMapping(
  store: AgentStore,
  input: ResolveSurfaceSessionInput,
  agentSessionId: string,
  now: number,
): ResolveSurfaceSessionResult {
  const shared = readSharedChatMapping(store, input);
  if (shared && shared.agentSessionId !== agentSessionId) {
    throw new Error("Shared chat continuity mapping points at a different canonical session");
  }
  const conversationId = shared?.conversationId ?? generateAgentId("conversation");
  try {
    store.insertSurfaceConversation({
      ownerId: input.ownerId,
      surfaceKind: input.surfaceRef.surfaceKind,
      externalRefKind: input.surfaceRef.externalRefKind,
      externalRefId: input.surfaceRef.externalRefId,
      conversationId,
      agentSessionId,
      createdAtMs: now,
      lastActiveAtMs: now,
    });
    return { conversationId, agentSessionId };
  } catch (error) {
    if (!isSqliteUniqueConstraintError(error)) throw error;
    const mapped = readSurfaceConversation(store, input);
    if (!mapped) throw error;
    touchSurfaceConversation(store, input, now);
    return mapped;
  }
}

function recoverResolveSurfaceSessionAfterConflict(
  store: AgentStore,
  input: ResolveSurfaceSessionInput,
  now: number,
  error: unknown,
): ResolveSurfaceSessionResult {
  if (!isSqliteUniqueConstraintError(error)) throw error;
  const mapped = readSurfaceConversation(store, input);
  if (mapped) {
    touchSurfaceConversation(store, input, now);
    return mapped;
  }
  const existingSessionId = readSessionIdByExternalRef(store, input);
  if (!existingSessionId) throw error;
  return createSurfaceConversationMapping(store, input, existingSessionId, now);
}

export function resolveSurfaceSession(
  store: AgentStore,
  input: ResolveSurfaceSessionInput,
  nowMs: () => number,
): ResolveSurfaceSessionResult {
  return store.withTransaction(() => {
    const now = nowMs();
    const mapped = readSurfaceConversation(store, input);
    if (mapped) {
      touchSurfaceConversation(store, input, now);
      return mapped;
    }

    const existingSessionId = readSessionIdByExternalRef(store, input);
    if (existingSessionId) {
      const resolved = createSurfaceConversationMapping(store, input, existingSessionId, now);
      return resolved;
    }

    try {
      const session = store.insertSession({
        ownerId: input.ownerId,
        surfaceKind: input.surfaceRef.surfaceKind,
        externalRefKind: input.surfaceRef.externalRefKind,
        externalRefId: input.surfaceRef.externalRefId,
        title: input.title ?? null,
        defaultAdapterId: input.defaultAdapterId ?? "pi-mono",
        executionRole: input.executionRole,
        providerBoundary: input.providerBoundary,
        modelProfile: input.modelProfile,
        defaultCwd: input.defaultCwd,
        executionProfileSource: input.executionProfileSource,
      });
      return createSurfaceConversationMapping(store, input, session.sessionId, now);
    } catch (error) {
      return recoverResolveSurfaceSessionAfterConflict(store, input, now, error);
    }
  });
}

/// Resolve a surface only when its catalog/session identity already exists.
/// Journal reads and writes for named chats use this path so a stale request
/// cannot resurrect a session after atomic catalog deletion.
export function resolveExistingSurfaceSession(
  store: AgentStore,
  input: ResolveSurfaceSessionInput,
  nowMs: () => number,
): ResolveSurfaceSessionResult {
  return store.withTransaction(() => {
    const now = nowMs();
    const mapped = readSurfaceConversation(store, input);
    if (mapped) {
      touchSurfaceConversation(store, input, now);
      return mapped;
    }
    const existingSessionId = readSessionIdByExternalRef(store, input);
    if (!existingSessionId) throw new Error("chat_catalog_not_found");
    return createSurfaceConversationMapping(store, input, existingSessionId, now);
  });
}

export function clearOwnerSurfaceState(store: AgentStore, ownerId: string, nowMs: () => number): {
  invalidatedBindingIds: string[];
} {
  const now = nowMs();
  const sessionRows = store.allRows("SELECT session_id FROM sessions WHERE owner_id = ?", [ownerId]);
  const sessionIds = sessionRows.map((row) => String(row.session_id));
  if (sessionIds.length === 0) {
    return { invalidatedBindingIds: [] };
  }

  const placeholders = sessionIds.map(() => "?").join(", ");
  const bindingRows = store.allRows(
    `SELECT binding_id FROM adapter_bindings
     WHERE session_id IN (${placeholders}) AND status = 'active'`,
    sessionIds,
  );
  const invalidatedBindingIds = bindingRows.map((row) => String(row.binding_id));
  if (invalidatedBindingIds.length > 0) {
    store.execute(
      `UPDATE adapter_bindings
       SET status = 'invalid', invalidated_at_ms = ?, updated_at_ms = ?
       WHERE binding_id IN (${invalidatedBindingIds.map(() => "?").join(", ")})`,
      [now, now, ...invalidatedBindingIds],
    );
  }
  return { invalidatedBindingIds };
}
