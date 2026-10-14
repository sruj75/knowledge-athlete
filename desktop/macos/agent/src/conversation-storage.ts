import { SqliteAgentStore } from "./runtime/sqlite-store.js";
import { resolveSurfaceSession, resolveExistingSurfaceSession, type SurfaceRef } from "./runtime/surface-session.js";
import {
  recordJournalExchange, listJournalTurns, assertPublicJournalUpdatePolicy,
  updateJournalTurnWithReceipt, clearJournalConversation, repairOrphanedJournalTurns,
  journalTurnChangedWakes, type RecordJournalTurnInput, type UpdateJournalTurnInput,
  type RecordJournalExchangeResult,
} from "./runtime/conversation-journal.js";
import type { ConversationTurn } from "./runtime/types.js";

export interface LocalChatSummary {
  chatId: string;
  title: string;
  titleOrigin: "default" | "automatic" | "manual";
  preview: string;
  messageCount: number;
  createdAtMs: number;
  lastActivityAtMs: number;
  starred: boolean;
}
type ChatCatalogTitleOrigin = LocalChatSummary["titleOrigin"];
export type ConversationWrite = Omit<RecordJournalTurnInput, "ownerId" | "conversationId" | "surfaceKind">;

/** The retained local catalog/journal. No model, worker, tool, or subprocess owner. */
export class ConversationStorage {
  private readonly store: SqliteAgentStore;
  readonly ownerId: string;
  private readonly activeTurns = new Set<string>();

  constructor(options: { stateDir: string; ownerId: string }) {
    this.ownerId = requiredCatalogText(options.ownerId, "ownerId");
    this.store = new SqliteAgentStore({ stateDir: options.stateDir, reconcileOnOpen: false });
  }

  close(): void { this.store.close(); }

  createChat(input: { chatId: string; title?: string }): LocalChatSummary {
    const chatId = requiredCatalogText(input.chatId, "chatId");
    resolveSurfaceSession(this.store, {
      ownerId: this.ownerId,
      surfaceRef: { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: chatId },
      defaultAdapterId: "conversation",
      providerBoundary: "managed_cloud",
      title: normalizedCatalogTitle(input.title),
    }, Date.now);
    return this.listChats().find((chat) => chat.chatId === chatId)!;
  }

  private resolve(surface: SurfaceRef) {
    const input = { ownerId: this.ownerId, surfaceRef: surface, defaultAdapterId: "conversation", providerBoundary: "managed_cloud" as const };
    return surface.externalRefId === "default"
      ? resolveSurfaceSession(this.store, input, Date.now)
      : resolveExistingSurfaceSession(this.store, input, Date.now);
  }

  resolveSurface(surface: SurfaceRef) { return this.resolve(surface); }

  wakes(turns: readonly ConversationTurn[]) {
    return turns.flatMap((turn) => journalTurnChangedWakes(this.store, this.ownerId, turn));
  }

  recordExchange(surface: SurfaceRef, turns: readonly ConversationWrite[], expectedGeneration: number) {
    const { conversationId } = this.resolve(surface);
    return this.store.withTransaction(() => {
      this.assertGeneration(conversationId, expectedGeneration);
      const receipt = recordJournalExchange(this.store, {
        ownerId: this.ownerId, conversationId,
        turns: turns.map((turn) => ({ ...turn, surfaceKind: surface.surfaceKind })),
      });
      this.trackActiveTurns(receipt.turns);
      return receipt;
    });
  }

  recordOrReviseExchange(surface: SurfaceRef, turns: readonly ConversationWrite[], expectedGeneration: number): RecordJournalExchangeResult {
    const { conversationId } = this.resolve(surface);
    const roles = turns.map((turn) => turn.role);
    if (turns.length < 1 || turns.length > 2 || new Set(roles).size !== roles.length
      || (roles.length === 2 && (roles[0] !== "user" || roles[1] !== "assistant"))) {
      throw new Error("invalid_conversation_exchange");
    }
    const activeBefore = new Set(this.activeTurns);
    try { return this.store.withTransaction(() => {
      this.assertGeneration(conversationId, expectedGeneration);
      const result: RecordJournalExchangeResult = { turns: [], createdTurns: [], firstCompletedRealPair: false, firstCompletedRealExchange: null };
      for (const turn of turns) {
        if (!turn.turnId) throw new Error("conversation_revision_requires_turn_id");
        const existing = this.store.getOptionalRow(
          "SELECT role, origin, producing_run_id FROM conversation_turns WHERE conversation_id = ? AND turn_id = ?",
          [conversationId, turn.turnId],
        );
        if (existing) {
          if (String(existing.role) !== turn.role || String(existing.origin) !== turn.origin || existing.producing_run_id !== null) {
            throw new Error("conversation_revision_identity_mismatch");
          }
          const updated = this.updateTurn(surface, {
            turnId: turn.turnId, status: turn.status, content: turn.content,
            replaceContentBlocks: turn.contentBlocks, replaceResources: turn.resources ?? [],
            metadataJson: turn.metadataJson ?? "{}",
          }, expectedGeneration);
          result.turns.push(updated.turn);
          if (updated.firstCompletedRealPair) {
            result.firstCompletedRealPair = true;
            result.firstCompletedRealExchange = updated.firstCompletedRealExchange;
          }
        } else {
          const inserted = this.recordExchange(surface, [turn], expectedGeneration);
          result.turns.push(...inserted.turns);
          result.createdTurns.push(...inserted.createdTurns);
          if (inserted.firstCompletedRealPair) {
            result.firstCompletedRealPair = true;
            result.firstCompletedRealExchange = inserted.firstCompletedRealExchange;
          }
        }
      }
      return result;
    }); } catch (error) {
      this.activeTurns.clear();
      for (const key of activeBefore) this.activeTurns.add(key);
      throw error;
    }
  }


  listTurns(surface: SurfaceRef, afterTurnSeq = 0, limit = 100) {
    const { conversationId } = this.resolve(surface);
    return listJournalTurns(this.store, { ownerId: this.ownerId, conversationId, afterTurnSeq, limit });
  }

  /** Context reads select the latest revision of each logical turn, ordered by
   * original admission. Partial-token volume cannot evict earlier exchanges. */
  tailTurns(surface: SurfaceRef, limit = 8) {
    const { conversationId } = this.resolve(surface);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("invalid_tail_limit");
    return this.store.withTransaction(() => {
      const state = listJournalTurns(this.store, { ownerId: this.ownerId, conversationId, limit: 1 });
      const turns = this.store.allRows(
        `SELECT revision.turn_json
         FROM (
           SELECT MIN(turn_seq) AS first_seq, MAX(turn_seq) AS latest_seq
           FROM conversation_turn_revisions
           WHERE conversation_id = ? AND generation = ?
           GROUP BY turn_id ORDER BY first_seq DESC LIMIT ?
         ) latest
         JOIN conversation_turn_revisions revision
           ON revision.conversation_id = ? AND revision.turn_seq = latest.latest_seq
         ORDER BY latest.first_seq ASC`,
        [conversationId, state.generation, limit, conversationId],
      ).map((row) => JSON.parse(String(row.turn_json)) as ConversationTurn);
      return { ...state, turns };
    });
  }

  updateTurn(surface: SurfaceRef, update: Omit<UpdateJournalTurnInput, "ownerId" | "conversationId" | "producingRunId" | "producingAttemptId">, expectedGeneration: number) {
    const { conversationId } = this.resolve(surface);
    const input = { ...update, ownerId: this.ownerId, conversationId };
    return this.store.withTransaction(() => {
      this.assertGeneration(conversationId, expectedGeneration);
      assertPublicJournalUpdatePolicy(this.store, input);
      const receipt = updateJournalTurnWithReceipt(this.store, input);
      this.trackActiveTurns([receipt.turn]);
      return receipt;
    });
  }

  clear(surface: SurfaceRef, expectedGeneration: number) {
    const { conversationId } = this.resolve(surface);
    const result = clearJournalConversation(this.store, { ownerId: this.ownerId, conversationId, expectedGeneration });
    for (const key of this.activeTurns) if (key.startsWith(`${conversationId}:`)) this.activeTurns.delete(key);
    return result;
  }

  repair(surface: SurfaceRef, turnIds: readonly string[], expectedGeneration: number) {
    const { conversationId } = this.resolve(surface);
    return this.store.withTransaction(() => {
      this.assertGeneration(conversationId, expectedGeneration);
      const ownedTurnIds = turnIds.filter((turnId) => !this.activeTurns.has(`${conversationId}:${turnId}`) && this.store.getOptionalRow(
        "SELECT turn_id FROM conversation_turns WHERE conversation_id = ? AND turn_id = ?",
        [conversationId, turnId],
      ));
      return repairOrphanedJournalTurns(this.store, { ownerId: this.ownerId, turnIds: ownedTurnIds });
    });
  }

  private trackActiveTurns(turns: readonly ConversationTurn[]): void {
    for (const turn of turns) {
      const key = `${turn.conversationId}:${turn.turnId}`;
      if (turn.status === "pending" || turn.status === "streaming") this.activeTurns.add(key);
      else this.activeTurns.delete(key);
    }
  }

  private assertGeneration(conversationId: string, expectedGeneration: number): void {
    const state = listJournalTurns(this.store, { ownerId: this.ownerId, conversationId, limit: 1 });
    if (!Number.isSafeInteger(expectedGeneration) || expectedGeneration !== state.generation) {
      throw new Error("journal_generation_stale");
    }
  }

  listChats(): LocalChatSummary[] {
    const sessions = this.store.allRows(
      `SELECT session_id, external_ref_id, title, title_origin, starred,
              created_at_ms, last_activity_at_ms
       FROM sessions
       WHERE owner_id = ? AND external_ref_kind = 'chat' AND status = 'open'
       ORDER BY last_activity_at_ms DESC, created_at_ms DESC, external_ref_id ASC`,
      [requiredCatalogText(this.ownerId, "ownerId")],
    );
    return sessions
      .map((session) => this.chatSummaryFromSessionRow(this.ownerId, session))
      .sort((left, right) =>
        right.lastActivityAtMs - left.lastActivityAtMs
        || right.createdAtMs - left.createdAtMs
        || left.chatId.localeCompare(right.chatId));
  }

  updateChat(input: { chatId: string; title?: string; titleOrigin?: "automatic" | "manual"; expectedTitleOrigin?: ChatCatalogTitleOrigin; starred?: boolean }): LocalChatSummary {
    const ownerId = requiredCatalogText(this.ownerId, "ownerId");
    const chatId = requiredCatalogText(input.chatId, "chatId");
    const session = this.ownedChatSessionRow(ownerId, chatId);
    const currentOrigin = String(session.title_origin) as ChatCatalogTitleOrigin;
    if (input.expectedTitleOrigin && currentOrigin !== input.expectedTitleOrigin) {
      return this.chatSummaryFromSessionRow(ownerId, session);
    }

    const assignments: string[] = [];
    const values: (string | number)[] = [];
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

  deleteChat(requestedChatId: string): {
    deletedChatId: string;
    retainedAttachmentUris: string[];
  } {
    const ownerId = requiredCatalogText(this.ownerId, "ownerId");
    const chatId = requiredCatalogText(requestedChatId, "chatId");
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
        for (const key of this.activeTurns) if (key.startsWith(`${conversationId}:`)) this.activeTurns.delete(key);
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
