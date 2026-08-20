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
  resolveExistingSurfaceSession,
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
} from "./types.js";
import { buildDesktopActionQueue } from "./desktop-action-queue.js";
import { buildDesktopContextPacket, type DesktopContextPacketBuildInput } from "./desktop-context-packet.js";
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

import { KernelArtifacts } from "./kernel-artifacts.js";
import { readSessionExecutionProfile } from "./session-execution-profile.js";
import type { SessionExecutionProfile } from "./types.js";
import {
  buildContextSnapshot,
  updateContextSource,
  type ContextSourceUpdateInput,
  type ContextSourceUpdateResult,
} from "./context-snapshot.js";
import type { ContextSnapshotProjection } from "../protocol.js";
import {
  ensureAgentSpawnJournal,
  type EnsureAgentSpawnJournalInput,
  type EnsureAgentSpawnJournalResult,
} from "./agent-spawn-journal.js";

export type ChatCatalogTitleOrigin = "default" | "automatic" | "manual";

export interface LocalChatSummary {
  chatId: string;
  title: string;
  titleOrigin: ChatCatalogTitleOrigin;
  preview: string;
  messageCount: number;
  createdAtMs: number;
  lastActivityAtMs: number;
  starred: boolean;
}

export interface CreateChatCatalogInput {
  ownerId: string;
  chatId: string;
  title?: string | null;
  defaultAdapterId: string;
  modelProfile?: string | null;
  defaultCwd?: string | null;
}

export interface UpdateChatCatalogInput {
  ownerId: string;
  chatId: string;
  title?: string;
  titleOrigin?: Exclude<ChatCatalogTitleOrigin, "default">;
  expectedTitleOrigin?: ChatCatalogTitleOrigin;
  starred?: boolean;
}

export class KernelSessions extends KernelArtifacts {
  listChatCatalog(input: { ownerId: string }): LocalChatSummary[] {
    const sessions = this.store.allRows(
      `SELECT session_id, external_ref_id, title, title_origin, starred,
              created_at_ms, last_activity_at_ms
       FROM sessions
       WHERE owner_id = ? AND external_ref_kind = 'chat' AND status = 'open'
       ORDER BY last_activity_at_ms DESC, created_at_ms DESC, external_ref_id ASC`,
      [requiredCatalogText(input.ownerId, "ownerId")],
    );
    return sessions
      .map((session) => this.chatSummaryFromSessionRow(input.ownerId, session))
      .sort((left, right) =>
        right.lastActivityAtMs - left.lastActivityAtMs
        || right.createdAtMs - left.createdAtMs
        || left.chatId.localeCompare(right.chatId));
  }

  createChatCatalog(input: CreateChatCatalogInput): LocalChatSummary {
    const ownerId = requiredCatalogText(input.ownerId, "ownerId");
    const chatId = requiredCatalogText(input.chatId, "chatId");
    this.resolveSurfaceSession({
      ownerId,
      surfaceRef: { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: chatId },
      defaultAdapterId: requiredCatalogText(input.defaultAdapterId, "defaultAdapterId"),
      providerBoundary: "managed_cloud",
      modelProfile: input.modelProfile ?? null,
      defaultCwd: input.defaultCwd ?? null,
      executionRole: "coordinator",
      title: normalizedCatalogTitle(input.title),
    });
    const session = this.ownedChatSessionRow(ownerId, chatId);
    return this.chatSummaryFromSessionRow(ownerId, session);
  }

  updateChatCatalog(input: UpdateChatCatalogInput): LocalChatSummary {
    const ownerId = requiredCatalogText(input.ownerId, "ownerId");
    const chatId = requiredCatalogText(input.chatId, "chatId");
    const session = this.ownedChatSessionRow(ownerId, chatId);
    const currentOrigin = String(session.title_origin) as ChatCatalogTitleOrigin;
    if (input.expectedTitleOrigin && currentOrigin !== input.expectedTitleOrigin) {
      return this.chatSummaryFromSessionRow(ownerId, session);
    }

    const assignments: string[] = [];
    const values: unknown[] = [];
    if (input.title !== undefined) {
      const origin = input.titleOrigin ?? "manual";
      assignments.push("title = ?", "title_origin = ?");
      values.push(
        origin === "automatic" ? normalizedAutomaticChatTitle(input.title) : normalizedCatalogTitle(input.title),
        origin,
      );
    }
    if (input.starred !== undefined) {
      assignments.push("starred = ?");
      values.push(input.starred ? 1 : 0);
    }
    if (assignments.length > 0) {
      assignments.push("updated_at_ms = ?");
      values.push(Date.now(), String(session.session_id), ownerId);
      this.store.execute(
        `UPDATE sessions SET ${assignments.join(", ")} WHERE session_id = ? AND owner_id = ?`,
        values,
      );
    }
    return this.chatSummaryFromSessionRow(ownerId, this.ownedChatSessionRow(ownerId, chatId));
  }

  deleteChatCatalog(input: { ownerId: string; chatId: string }): {
    deletedChatId: string;
    retainedAttachmentUris: string[];
  } {
    const ownerId = requiredCatalogText(input.ownerId, "ownerId");
    const chatId = requiredCatalogText(input.chatId, "chatId");
    if (chatId === "default") throw new Error("default_chat_cannot_be_deleted");
    const session = this.store.getOptionalRow(
      `SELECT session_id, external_ref_id, title, title_origin, starred,
              created_at_ms, last_activity_at_ms
       FROM sessions
       WHERE owner_id = ? AND external_ref_kind = 'chat' AND external_ref_id = ? AND status = 'open'`,
      [ownerId, chatId],
    );
    if (!session) {
      return { deletedChatId: chatId, retainedAttachmentUris: this.retainedAttachmentUris(ownerId) };
    }
    const conversationIds = this.store.allRows(
      `SELECT DISTINCT conversation_id FROM surface_conversations
       WHERE owner_id = ? AND agent_session_id = ?`,
      [ownerId, String(session.session_id)],
    ).map((row) => String(row.conversation_id));
    this.store.withTransaction(() => {
      for (const conversationId of conversationIds) {
        this.store.execute("DELETE FROM conversation_turn_revisions WHERE conversation_id = ?", [conversationId]);
        this.store.execute("DELETE FROM conversation_turns WHERE conversation_id = ?", [conversationId]);
        this.store.execute("DELETE FROM conversation_journal_state WHERE conversation_id = ?", [conversationId]);
      }
      const deleted = this.store.execute(
        "DELETE FROM sessions WHERE session_id = ? AND owner_id = ?",
        [String(session.session_id), ownerId],
      );
      if (deleted !== 1) throw new Error("chat_catalog_delete_failed");
    });
    return { deletedChatId: chatId, retainedAttachmentUris: this.retainedAttachmentUris(ownerId) };
  }

  retainedAttachmentUris(ownerId: string): string[] {
    const values = new Set<string>();
    const rows = this.store.allRows(
      `SELECT ct.resources_json
       FROM conversation_turns ct
       WHERE EXISTS (
         SELECT 1 FROM surface_conversations sc
         WHERE sc.owner_id = ? AND sc.conversation_id = ct.conversation_id
       )`,
      [ownerId],
    );
    for (const row of rows) {
      let resources: unknown;
      try {
        resources = JSON.parse(String(row.resources_json));
      } catch {
        continue;
      }
      if (!Array.isArray(resources)) continue;
      for (const resource of resources) {
        if (!resource || typeof resource !== "object") continue;
        const candidate = resource as Record<string, unknown>;
        if (candidate.origin === "userAttachment" && typeof candidate.uri === "string") {
          values.add(candidate.uri);
        }
      }
    }
    return [...values].sort();
  }

  private ownedChatSessionRow(ownerId: string, chatId: string): Record<string, unknown> {
    const session = this.store.getOptionalRow(
      `SELECT session_id, external_ref_id, title, title_origin, starred,
              created_at_ms, last_activity_at_ms
       FROM sessions
       WHERE owner_id = ? AND external_ref_kind = 'chat' AND external_ref_id = ? AND status = 'open'`,
      [ownerId, chatId],
    );
    if (!session) throw new Error("chat_catalog_not_found");
    return session;
  }

  private chatSummaryFromSessionRow(ownerId: string, session: Record<string, unknown>): LocalChatSummary {
    const chatId = String(session.external_ref_id);
    const surface = this.store.getOptionalRow(
      `SELECT conversation_id
       FROM surface_conversations
       WHERE owner_id = ? AND external_ref_kind = 'chat' AND external_ref_id = ?
       ORDER BY CASE surface_kind WHEN 'main_chat' THEN 0 WHEN 'floating_chat' THEN 1 ELSE 2 END,
                created_at_ms ASC
       LIMIT 1`,
      [ownerId, chatId],
    );
    const conversationId = surface ? String(surface.conversation_id) : null;
    const stats = conversationId
      ? this.store.getRow(
          `SELECT COUNT(*) AS message_count, COALESCE(MAX(updated_at_ms), 0) AS last_activity_at_ms
           FROM conversation_turns
           WHERE conversation_id = ? AND role IN ('user', 'assistant')
             AND status = 'completed' AND trim(content) != ''`,
          [conversationId],
        )
      : { message_count: 0, last_activity_at_ms: 0 };
    const latest = conversationId
      ? this.store.getOptionalRow(
          `SELECT content FROM conversation_turns
           WHERE conversation_id = ? AND role IN ('user', 'assistant')
             AND status = 'completed' AND trim(content) != ''
           ORDER BY turn_seq DESC, updated_at_ms DESC LIMIT 1`,
          [conversationId],
        )
      : undefined;
    return {
      chatId,
      title: normalizedCatalogTitle(session.title),
      titleOrigin: String(session.title_origin) as ChatCatalogTitleOrigin,
      preview: latest ? String(latest.content) : "",
      messageCount: Number(stats.message_count),
      createdAtMs: Number(session.created_at_ms),
      // Catalog activity belongs only to accepted visible turns. Session run
      // admission also advances last_activity_at_ms, so using that column here
      // lets aborted/internal work reorder an otherwise unchanged chat.
      lastActivityAtMs: Math.max(Number(session.created_at_ms), Number(stats.last_activity_at_ms)),
      starred: Number(session.starred) === 1,
    };
  }

  ownedSession(sessionId: string, ownerId: string): AgentSession {
    const session = this.readSession(sessionId);
    this.assertSessionOwner(session, ownerId);
    return session;
  }

  contextSnapshot(sessionId: string, ownerId: string, surfaceKind?: string): ContextSnapshotProjection {
    return buildContextSnapshot(this.store, sessionId, ownerId, Date.now(), surfaceKind);
  }

  contextSnapshotForExactSurface(
    ownerId: string,
    surface: { surfaceKind: string; externalRefKind: string; externalRefId: string },
  ): ContextSnapshotProjection {
    const mapping = this.store.getRow(
      `SELECT agent_session_id FROM surface_conversations
       WHERE owner_id = ? AND surface_kind = ? AND external_ref_kind = ? AND external_ref_id = ?`,
      [ownerId, surface.surfaceKind, surface.externalRefKind, surface.externalRefId],
    );
    return buildContextSnapshot(
      this.store,
      String(mapping.agent_session_id),
      ownerId,
      Date.now(),
      surface.surfaceKind,
    );
  }

  updateContextSource(input: ContextSourceUpdateInput): ContextSourceUpdateResult {
    return updateContextSource(this.store, input);
  }

  ensureAgentSpawnJournal(input: EnsureAgentSpawnJournalInput): EnsureAgentSpawnJournalResult {
    return ensureAgentSpawnJournal(this.store, input);
  }

  sessionExecutionProfile(sessionId: string, ownerId: string): SessionExecutionProfile {
    const session = this.readSession(sessionId);
    this.assertSessionOwner(session, ownerId);
    return readSessionExecutionProfile(this.store, sessionId);
  }

  executionPolicyForSession(sessionId: string): Pick<AgentSession, "executionRole" | "providerBoundary" | "defaultAdapterId"> {
    const session = this.readSession(sessionId);
    return {
      executionRole: session.executionRole,
      providerBoundary: session.providerBoundary,
      defaultAdapterId: session.defaultAdapterId,
    };
  }

  executionPolicyForOwnedSession(
    sessionId: string,
    ownerId: string,
  ): Pick<AgentSession, "executionRole" | "providerBoundary" | "defaultAdapterId"> {
    const session = this.readSession(sessionId);
    this.assertSessionOwner(session, ownerId);
    return {
      executionRole: session.executionRole,
      providerBoundary: session.providerBoundary,
      defaultAdapterId: session.defaultAdapterId,
    };
  }

  listSessions(input: ListSessionsInput = {}): KernelSessionSummary[] {
    const where: string[] = [];
    const values: unknown[] = [];
    if (input.ownerId) {
      where.push("owner_id = ?");
      values.push(input.ownerId);
    }
    if (input.status) {
      where.push("status = ?");
      values.push(input.status);
    }
    if (input.surfaceKind) {
      where.push("surface_kind = ?");
      values.push(input.surfaceKind);
    }
    if (input.executionRole) {
      where.push("execution_role = ?");
      values.push(input.executionRole);
    }
    if (input.beforeUpdatedAtMs !== undefined) {
      where.push("updated_at_ms < ?");
      values.push(input.beforeUpdatedAtMs);
    }
    const limit = boundedLimit(input.limit, 50, 200);
    const sessions = this.store
      .allRows(
        `SELECT * FROM sessions
         ${where.length ? `WHERE ${where.join(" AND ")}` : ""}
         ORDER BY last_activity_at_ms DESC, created_at_ms DESC
         LIMIT ?`,
        [...values, limit],
      )
      .map((row) => this.readSession(String(row.session_id)));

    return sessions.map((session) => ({
      session,
      latestRun: this.readLatestRunForSession(session.sessionId),
      activeRun: this.readActiveRunForSession(session.sessionId),
      adapterBindings: this.readBindingsForSession(session.sessionId),
    }));
  }
  resolveSurfaceSession(input: ResolveSurfaceSessionInput): ResolveSurfaceSessionResult {
    return resolveSurfaceSession(this.store, input, () => Date.now());
  }

  resolveExistingSurfaceSession(input: ResolveSurfaceSessionInput): ResolveSurfaceSessionResult {
    return resolveExistingSurfaceSession(this.store, input, () => Date.now());
  }

  clearOwnerState(ownerId: string): { invalidatedBindingIds: string[] } {
    return clearOwnerSurfaceState(this.store, ownerId, () => Date.now());
  }

  invalidateBindings(input: InvalidateBindingsInput): InvalidateBindingsResult {
    const session = this.findExistingSession(input);
    const sessionIds = session ? [session.sessionId] : this.findInvalidationSessionIds(input);
    if (sessionIds.length === 0) {
      return { invalidatedBindingIds: [] };
    }

    const rows = this.store.allRows(
      `SELECT binding_id, session_id
       FROM adapter_bindings
       WHERE session_id IN (${placeholders(sessionIds.length)})
         AND status = ?
         ${input.adapterId ? "AND adapter_id = ?" : ""}`,
      input.adapterId ? [...sessionIds, "active", input.adapterId] : [...sessionIds, "active"],
    );
    const invalidatedBindingIds = rows.map((row) => String(row.binding_id));
    if (invalidatedBindingIds.length === 0) {
      return { sessionId: session?.sessionId, invalidatedBindingIds };
    }

    const now = Date.now();
    this.withTransaction(() => {
      for (const bindingId of invalidatedBindingIds) {
        this.updateBinding(bindingId, {
          status: "invalid",
          invalidatedAtMs: now,
          updatedAtMs: now,
        });
        this.appendEvent({
          sessionId: String(rows.find((row) => String(row.binding_id) === bindingId)?.session_id),
          runId: null,
          attemptId: null,
          type: "binding.stale",
          payload: {
            bindingId,
            adapterId: input.adapterId,
            reason: input.reason ?? "invalidate_session",
          },
        });
      }
    });

    return { sessionId: session?.sessionId, invalidatedBindingIds };
  }

  staleProcessLocalBindings(input: StaleProcessLocalBindingsInput): StaleProcessLocalBindingsResult {
    const rows = this.store.allRows(
      `SELECT binding_id, session_id
       FROM adapter_bindings
       WHERE adapter_id = ?
         AND resume_fidelity = ?
         AND status = ?`,
      [input.adapterId, "none", "active"],
    );
    const staleBindingIds = rows.map((row) => String(row.binding_id));
    if (staleBindingIds.length === 0) {
      return { staleBindingIds };
    }

    const now = Date.now();
    this.withTransaction(() => {
      for (const row of rows) {
        const bindingId = String(row.binding_id);
        this.updateBinding(bindingId, {
          status: "stale",
          invalidatedAtMs: now,
          updatedAtMs: now,
        });
        this.appendEvent({
          sessionId: String(row.session_id),
          runId: null,
          attemptId: null,
          type: "binding.stale",
          payload: {
            bindingId,
            adapterId: input.adapterId,
            reason: input.reason,
          },
        });
      }
    });

    return { staleBindingIds };
  }
}

function requiredCatalogText(value: string, field: string): string {
  const normalized = value.trim();
  if (!normalized) throw new Error(`chat_catalog_${field}_required`);
  return normalized;
}

function normalizedCatalogTitle(value: unknown): string {
  if (typeof value !== "string") return "New Chat";
  return value.trim() || "New Chat";
}

function normalizedAutomaticChatTitle(value: string): string {
  const words = value.trim().split(/\s+/).filter(Boolean).slice(0, 6);
  return words.length > 0 ? words.join(" ") : "New Chat";
}
