import { createHash } from "node:crypto";
import { conversationTurnFromRow } from "./conversation-turns.js";
import { generateAgentId } from "./sqlite-store.js";
import type {
  AgentStore,
  ConversationContentBlock,
  ConversationResource,
  ConversationTurn,
  ConversationTurnOrigin,
  ConversationTurnRole,
  ConversationTurnStatus,
} from "./types.js";

const TURN_COLUMNS = `
  conversation_id, turn_id, turn_seq, producer_id, payload_hash,
  role, surface_kind, content, created_at_ms, metadata_json,
  origin, status, content_blocks_json, resources_json, producing_run_id,
  producing_attempt_id, remote_id, updated_at_ms, completed_at_ms
`;
const MAX_LIST_BATCH = 100;

export interface RecordJournalTurnInput {
  ownerId: string;
  conversationId: string;
  turnId?: string;
  producerId?: string;
  role: ConversationTurnRole;
  surfaceKind: string;
  origin: ConversationTurnOrigin;
  status?: ConversationTurnStatus;
  content: string;
  contentBlocks: readonly ConversationContentBlock[];
  resources?: readonly ConversationResource[];
  producingRunId?: string | null;
  producingAttemptId?: string | null;
  metadataJson?: string;
  createdAtMs?: number;
}

export interface RecordJournalTurnResult {
  turn: ConversationTurn;
  created: boolean;
  duplicate: boolean;
}

export interface RecordJournalExchangeInput {
  ownerId: string;
  conversationId: string;
  turns: readonly Omit<RecordJournalTurnInput, "ownerId" | "conversationId">[];
}

export interface RecordJournalExchangeResult {
  turns: ConversationTurn[];
  createdTurns: ConversationTurn[];
  firstCompletedRealPair: boolean;
  firstCompletedRealExchange: CompletedRealExchange | null;
}

export interface TerminalizeJournalTurnResult {
  turn: ConversationTurn;
  firstCompletedRealPair: boolean;
  firstCompletedRealExchange: CompletedRealExchange | null;
}

export interface UpdateJournalTurnResult {
  turn: ConversationTurn;
  firstCompletedRealPair: boolean;
  firstCompletedRealExchange: CompletedRealExchange | null;
}

export interface CompletedRealExchange {
  continuityKey: string;
  userText: string;
  assistantText: string;
}

export interface UpdateJournalTurnInput {
  ownerId: string;
  conversationId: string;
  turnId: string;
  status?: ConversationTurnStatus;
  content?: string;
  replaceContentBlocks?: readonly ConversationContentBlock[];
  appendContentBlocks?: readonly ConversationContentBlock[];
  replaceResources?: readonly ConversationResource[];
  appendResources?: readonly ConversationResource[];
  producingRunId?: string | null;
  producingAttemptId?: string | null;
  metadataJson?: string;
  nowMs?: number;
}

export interface RepairOrphanedJournalTurnsInput {
  ownerId: string;
  turnIds: readonly string[];
  nowMs?: number;
}

export interface TerminalizeJournalTurnInput {
  ownerId: string;
  conversationId: string;
  turnId: string;
  producingRunId: string;
  producingAttemptId: string;
  disposition: "accept" | "discard";
  content?: string;
  replaceContentBlocks?: readonly ConversationContentBlock[];
  replaceResources?: readonly ConversationResource[];
  nowMs?: number;
}

export interface ProducingJournalTurnAdmissionInput {
  ownerId: string;
  conversationId: string;
  sessionId: string;
  turnId: string;
}

export interface BindProducingJournalTurnInput extends ProducingJournalTurnAdmissionInput {
  runId: string;
  attemptId: string;
  nowMs?: number;
}

export interface DiscardProducingJournalTurnInput {
  ownerId: string;
  runId: string;
  attemptId: string;
  nowMs?: number;
}

export interface JournalTurnRange {
  conversationId: string;
  generation: number;
  generationBaseTurnSeq: number;
  highWaterTurnSeq: number;
  turns: ConversationTurn[];
}

export interface JournalTurnChangedWake {
  ownerId: string;
  conversationGeneration: number;
  generationBaseTurnSeq: number;
  surfaceKind: string;
  externalRefKind: string;
  externalRefId: string;
  turn: ConversationTurn;
}

/**
 * Present a conversation-owned turn through the exact surface binding that
 * requested or observed it. Shared chat surfaces intentionally converge on one
 * conversation, while Swift routes projection events by the turn surface.
 */
export function journalTurnForSurfaceProjection(
  turn: ConversationTurn,
  surfaceKind: string,
): ConversationTurn {
  return { ...turn, surfaceKind: nonEmpty(surfaceKind, "surfaceKind") };
}

export interface MigrateJournalConversationInput {
  ownerId: string;
  sourceConversationId: string;
  destinationConversationId: string;
  nowMs?: number;
}

export interface MigrateJournalConversationResult {
  movedTurnCount: number;
  movedRevisionCount: number;
  destinationGeneration: number;
  destinationHighWaterTurnSeq: number;
}

export interface JournalObservabilitySnapshot {
  turnStatusCounts: Partial<Record<ConversationTurnStatus, number>>;
}

/**
 * The only durable local insertion API for chat-visible turns. The turn and
 * its revision are committed in the same SQLite transaction.
 */
export function recordJournalTurn(
  store: AgentStore,
  input: RecordJournalTurnInput,
): RecordJournalTurnResult {
  const now = input.createdAtMs ?? Date.now();
  const turnId = nonEmpty(input.turnId ?? generateAgentId("turn"), "turnId");
  const contentBlocks = validateContentBlocks(input.contentBlocks);
  const resources = validateResources(input.resources ?? []);
  const metadataJson = validObjectJson(input.metadataJson ?? "{}", "metadataJson");
  const producerId = nonEmpty(input.producerId ?? `turn:${turnId}`, "producerId");

  return store.withTransaction(() => {
    assertConversationOwner(store, input.conversationId, input.ownerId);
    assertProducingRunOwner(store, input.producingRunId ?? null, input.ownerId);

    const existingByTurnId = findJournalTurnById(store, turnId);
    const existingByProducer = findJournalTurnByProducer(store, input.conversationId, producerId);
    if (
      existingByTurnId
      && existingByProducer
      && existingByTurnId.turnId !== existingByProducer.turnId
    ) {
      throw new Error("Canonical turn ID and producer ID resolve to different journal turns");
    }
    const existing = existingByTurnId ?? existingByProducer;
    if (existing) {
      const normalizedInput = {
        ...input,
        turnId: existing.turnId,
        contentBlocks,
        resources,
        metadataJson,
        producerId,
      };
      assertIdempotentRecord(existing, normalizedInput);
      return { turn: existing, created: false, duplicate: true };
    }

    const sequence = nextJournalSequence(store, input.conversationId, now);
    const payloadHash = journalTurnPayloadHash({
      turnId,
      role: input.role,
      surfaceKind: input.surfaceKind,
      content: input.content,
      origin: input.origin,
      status: input.status ?? "pending",
      contentBlocks,
      resources,
      producingRunId: input.producingRunId ?? null,
      producingAttemptId: input.producingAttemptId ?? null,
      remoteId: null,
      metadataJson,
    });
    const turn = store.insertConversationTurn({
      conversationId: input.conversationId,
      turnId,
      turnSeq: sequence.turnSeq,
      producerId,
      payloadHash,
      role: input.role,
      surfaceKind: nonEmpty(input.surfaceKind, "surfaceKind"),
      content: input.content,
      origin: input.origin,
      status: input.status ?? "pending",
      contentBlocks,
      resources,
      producingRunId: input.producingRunId ?? null,
      producingAttemptId: input.producingAttemptId ?? null,
      createdAtMs: now,
      updatedAtMs: now,
      completedAtMs: terminalTurnStatus(input.status ?? "pending") ? now : null,
      metadataJson,
    });
    appendJournalRevision(store, turn, sequence.generation, "recorded", now);
    return { turn, created: true, duplicate: false };
  });
}

/**
 * Records the visible halves of one logical exchange under one commit. A
 * failure or identity collision on either half rolls back every row, revision,
 * created by the other half.
 */
export function recordJournalExchange(
  store: AgentStore,
  input: RecordJournalExchangeInput,
): RecordJournalExchangeResult {
  if (input.turns.length > 2) {
    throw new Error("Journal exchange may contain at most two turns");
  }
  const roles = input.turns.map((turn) => turn.role);
  if (new Set(roles).size !== roles.length) {
    throw new Error("Journal exchange may contain at most one turn per role");
  }
  if (roles.length === 2 && (roles[0] !== "user" || roles[1] !== "assistant")) {
    throw new Error("Journal exchange turns must be ordered user then assistant");
  }

  return store.withTransaction(() => {
    assertConversationOwner(store, input.conversationId, input.ownerId);
    const existingCompletedRealExchange = firstCompletedRealExchange(store, input.conversationId);
    const exchangeBaseCreatedAtMs = input.turns[0]?.createdAtMs ?? Date.now();
    const normalizedTurns = input.turns.map((turn, index) => ({
      ...turn,
      // Creation time is the immutable conversation-order key. Preserve an
      // imported timestamp when possible, but make the assistant half strictly
      // later than its user half even when a coarse backend clock ties them.
      createdAtMs: index === 0
        ? exchangeBaseCreatedAtMs
        : Math.max(turn.createdAtMs ?? exchangeBaseCreatedAtMs + index, exchangeBaseCreatedAtMs + index),
    }));
    const results = normalizedTurns.map((turn) => recordJournalTurn(store, {
      ...turn,
      ownerId: input.ownerId,
      conversationId: input.conversationId,
    }));
    const completedRealExchange = firstCompletedRealExchange(store, input.conversationId);
    const firstCompletedRealPair = existingCompletedRealExchange === null && completedRealExchange !== null;
    return {
      turns: results.map((result) => result.turn),
      createdTurns: results.filter((result) => result.created).map((result) => result.turn),
      firstCompletedRealPair,
      firstCompletedRealExchange: firstCompletedRealPair ? completedRealExchange : null,
    };
  });
}

/** Update or complete the producing turn; block/resource IDs are idempotent. */
export function updateJournalTurn(store: AgentStore, input: UpdateJournalTurnInput): ConversationTurn {
  return updateJournalTurnMutation(store, input);
}

export function updateJournalTurnWithReceipt(
  store: AgentStore,
  input: UpdateJournalTurnInput,
): UpdateJournalTurnResult {
  return store.withTransaction(() => {
    assertConversationOwner(store, input.conversationId, input.ownerId);
    const existingCompletedRealExchange = firstCompletedRealExchange(store, input.conversationId);
    const turn = updateJournalTurnMutation(store, input);
    const completedRealExchange = firstCompletedRealExchange(store, input.conversationId);
    const firstCompletedRealPair = existingCompletedRealExchange === null && completedRealExchange !== null;
    return {
      turn,
      firstCompletedRealPair,
      firstCompletedRealExchange: firstCompletedRealPair ? completedRealExchange : null,
    };
  });
}

function updateJournalTurnMutation(store: AgentStore, input: UpdateJournalTurnInput): ConversationTurn {
  if (
    input.status === undefined
    && input.content === undefined
    && input.replaceContentBlocks === undefined
    && input.appendContentBlocks === undefined
    && input.replaceResources === undefined
    && input.appendResources === undefined
    && input.producingRunId === undefined
    && input.producingAttemptId === undefined
    && input.metadataJson === undefined
  ) {
    throw new Error("Journal turn update has no changes");
  }
  const now = input.nowMs ?? Date.now();
  return store.withTransaction(() => {
    assertConversationOwner(store, input.conversationId, input.ownerId);
    const current = requireJournalTurn(store, input.conversationId, input.turnId);
    if (input.status !== undefined) assertTurnStatusTransition(current.status, input.status);
    if (input.producingRunId !== undefined) {
      assertProducingRunOwner(store, input.producingRunId, input.ownerId);
      if (current.producingRunId !== null && current.producingRunId !== input.producingRunId) {
        throw new Error("A journal turn cannot change its producing run");
      }
    }
    if (input.producingAttemptId !== undefined) {
      if (input.producingAttemptId === null) {
        throw new Error("A journal turn producing attempt cannot be cleared");
      }
      if (current.producingAttemptId !== null && current.producingAttemptId !== input.producingAttemptId) {
        const attemptAdvance = store.getOptionalRow(
          `SELECT prior.run_id AS prior_run_id, prior.attempt_no AS prior_attempt_no,
                  next.run_id AS next_run_id, next.attempt_no AS next_attempt_no
           FROM run_attempts prior, run_attempts next
           WHERE prior.attempt_id = ? AND next.attempt_id = ?`,
          [current.producingAttemptId, input.producingAttemptId],
        );
        const targetRunId = input.producingRunId ?? current.producingRunId;
        if (
          !attemptAdvance
          || String(attemptAdvance.prior_run_id) !== targetRunId
          || String(attemptAdvance.next_run_id) !== targetRunId
          || Number(attemptAdvance.next_attempt_no) <= Number(attemptAdvance.prior_attempt_no)
          || terminalTurnStatus(current.status)
        ) {
          throw new Error("A journal turn cannot change its producing attempt");
        }
      }
    }

    const contentBlocks = input.replaceContentBlocks === undefined
      ? mergeById(current.contentBlocks, validateContentBlocks(input.appendContentBlocks ?? []))
      : mergeById([], validateContentBlocks(input.replaceContentBlocks));
    const resources = input.replaceResources === undefined
      ? mergeById(current.resources, validateResources(input.appendResources ?? []))
      : mergeById([], validateResources(input.replaceResources));
    const status = input.status ?? current.status;
    const metadataJson = input.metadataJson === undefined
      ? current.metadataJson
      : validObjectJson(input.metadataJson, "metadataJson");
    const content = input.content ?? current.content;
    const producingRunId = input.producingRunId === undefined ? current.producingRunId : input.producingRunId;
    const producingAttemptId = input.producingAttemptId === undefined
      ? current.producingAttemptId
      : input.producingAttemptId;
    const changed = status !== current.status
      || content !== current.content
      || stableJson(contentBlocks) !== stableJson(current.contentBlocks)
      || stableJson(resources) !== stableJson(current.resources)
      || producingRunId !== current.producingRunId
      || producingAttemptId !== current.producingAttemptId
      || stableJson(parseObjectJson(metadataJson)) !== stableJson(parseObjectJson(current.metadataJson));
    if (!changed) return current;

    const sequence = nextJournalSequence(store, input.conversationId, now);
    const payloadHash = journalTurnPayloadHash({
      turnId: current.turnId,
      role: current.role,
      surfaceKind: current.surfaceKind,
      content,
      origin: current.origin,
      status,
      contentBlocks,
      resources,
      producingRunId,
      producingAttemptId,
      remoteId: current.remoteId,
      metadataJson,
    });

    store.execute(
      `UPDATE conversation_turns
       SET content = ?, status = ?, content_blocks_json = ?, resources_json = ?,
           producing_run_id = ?, producing_attempt_id = ?, metadata_json = ?,
           turn_seq = ?, payload_hash = ?, updated_at_ms = ?,
           completed_at_ms = CASE
             WHEN ? IN ('completed', 'failed') THEN COALESCE(completed_at_ms, ?)
             ELSE NULL
           END
       WHERE conversation_id = ? AND turn_id = ?`,
      [
        content,
        status,
        JSON.stringify(contentBlocks),
        JSON.stringify(resources),
        producingRunId,
        producingAttemptId,
        metadataJson,
        sequence.turnSeq,
        payloadHash,
        now,
        status,
        now,
        input.conversationId,
        input.turnId,
      ],
    );

    const updated = requireJournalTurn(store, input.conversationId, input.turnId);
    appendJournalRevision(store, updated, sequence.generation, "updated", now);
    return updated;
  });
}

export function validateProducingJournalTurnAdmission(
  store: AgentStore,
  input: ProducingJournalTurnAdmissionInput,
): void {
  assertProducingJournalTurnMapping(store, input);
  const turn = requireJournalTurn(store, input.conversationId, nonEmpty(input.turnId, "producingTurnId"));
  if (turn.role !== "assistant" || !["pending", "streaming"].includes(turn.status)) {
    throw new Error("Producing turn admission requires a pending or streaming assistant turn");
  }
  if (turn.producingRunId !== null || turn.producingAttemptId !== null) {
    throw new Error("Producing turn is already bound to a canonical run attempt");
  }
}

export function bindProducingJournalTurn(
  store: AgentStore,
  input: BindProducingJournalTurnInput,
): ConversationTurn {
  return store.withTransaction(() => {
    assertProducingJournalTurnMapping(store, input);
    const authority = store.getOptionalRow(
      `SELECT r.session_id, s.owner_id, a.attempt_no,
              (SELECT latest.attempt_id FROM run_attempts latest
               WHERE latest.run_id = r.run_id ORDER BY latest.attempt_no DESC LIMIT 1) AS latest_attempt_id
       FROM runs r
       JOIN sessions s ON s.session_id = r.session_id
       JOIN run_attempts a ON a.run_id = r.run_id AND a.attempt_id = ?
       WHERE r.run_id = ?`,
      [input.attemptId, input.runId],
    );
    if (
      !authority
      || String(authority.owner_id) !== input.ownerId
      || String(authority.session_id) !== input.sessionId
      || String(authority.latest_attempt_id) !== input.attemptId
    ) {
      throw new Error("Producing turn admission run attempt is not the latest canonical session authority");
    }
    const turn = requireJournalTurn(store, input.conversationId, nonEmpty(input.turnId, "producingTurnId"));
    if (turn.role !== "assistant" || !["pending", "streaming"].includes(turn.status)) {
      throw new Error("Producing turn admission requires a pending or streaming assistant turn");
    }
    if (turn.producingRunId !== null && turn.producingRunId !== input.runId) {
      throw new Error("Producing turn is already bound to a different canonical run");
    }
    return updateJournalTurn(store, {
      ownerId: input.ownerId,
      conversationId: input.conversationId,
      turnId: turn.turnId,
      producingRunId: input.runId,
      producingAttemptId: input.attemptId,
      nowMs: input.nowMs,
    });
  });
}

/**
 * Repair assistant turns after their UI projection releases its send lock.
 *
 * Turn IDs are globally unique, so this resolves the canonical conversation
 * from the producing turn instead of trusting the caller's selected surface.
 * Active runs retain mutation authority.
 */
export function repairOrphanedJournalTurns(
  store: AgentStore,
  input: RepairOrphanedJournalTurnsInput,
): ConversationTurn[] {
  const turnIds = [...new Set(input.turnIds.map((turnId) => turnId.trim()).filter(Boolean))].slice(0, 100);
  const repaired: ConversationTurn[] = [];
  for (const turnId of turnIds) {
    const current = findJournalTurnById(store, turnId);
    if (!current) continue;
    assertConversationOwner(store, current.conversationId, input.ownerId);
    if (current.role !== "assistant" || terminalTurnStatus(current.status)) continue;

    const producingRun = current.producingRunId === null
      ? null
      : store.getOptionalRow("SELECT status FROM runs WHERE run_id = ?", [current.producingRunId]);
    const runStatus = producingRun ? String(producingRun.status) : null;
    if (
      runStatus !== null
      && ["queued", "starting", "running", "waiting_input", "waiting_approval", "cancelling"].includes(runStatus)
    ) {
      continue;
    }

    repaired.push(updateJournalTurn(store, {
      ownerId: input.ownerId,
      conversationId: current.conversationId,
      turnId,
      status: runStatus === "succeeded" ? "completed" : "failed",
      nowMs: input.nowMs,
    }));
  }
  return repaired;
}

export function assertPublicJournalUpdatePolicy(
  store: AgentStore,
  input: UpdateJournalTurnInput,
): void {
  assertConversationOwner(store, input.conversationId, input.ownerId);
  const current = requireJournalTurn(store, input.conversationId, input.turnId);
  const linkedTerminal = current.producingRunId !== null
    && current.producingAttemptId !== null
    && terminalTurnStatus(current.status);
  if (!linkedTerminal) return;
  const metadata = parseObjectJson(current.metadataJson) as Record<string, unknown>;
  const discarded = metadata.terminalMarker === "discarded_terminal";
  if (discarded) {
    throw new Error("Discarded terminal journal projection rejects every public update");
  }
  const appendBlocks = input.appendContentBlocks ?? [];
  const appendResources = input.appendResources ?? [];
  const hasAppend = appendBlocks.length > 0 || appendResources.length > 0;
  const hasForbiddenMutation = input.status !== undefined
    || input.content !== undefined
    || input.replaceContentBlocks !== undefined
    || input.replaceResources !== undefined
    || input.producingRunId !== undefined
    || input.producingAttemptId !== undefined
    || input.metadataJson !== undefined;
  if (current.status !== "completed" || hasForbiddenMutation || !hasAppend) {
    throw new Error("Linked terminal journal turns allow only typed completion/resource appends");
  }
  const completions = validateContentBlocks(appendBlocks);
  if (completions.some((block) => block.type !== "agentCompletion")) {
    throw new Error("Linked terminal journal turns accept only agentCompletion blocks");
  }
  const spawnBlocks = current.contentBlocks.filter(
    (block): block is Extract<ConversationContentBlock, { type: "agentSpawn" }> => block.type === "agentSpawn",
  );
  for (const completion of completions as Extract<ConversationContentBlock, { type: "agentCompletion" }>[]) {
    if (!completion.runId || !completion.sessionId) {
      throw new Error("Agent completion append requires canonical session and run identity");
    }
    if (!spawnBlocks.some((spawn) => (
      spawn.runId === completion.runId
      && spawn.sessionId === completion.sessionId
      && (!spawn.pillId || !completion.pillId || spawn.pillId === completion.pillId)
    ))) {
      throw new Error("Agent completion append must match an existing canonical agentSpawn block");
    }
  }
  const allowedRunIds = new Set<string>([
    current.producingRunId!,
    ...spawnBlocks.map((block) => block.runId),
  ]);
  for (const completion of completions) {
    if (completion.type === "agentCompletion" && completion.runId) allowedRunIds.add(completion.runId);
  }
  for (const resource of validateResources(appendResources)) {
    if (resource.runId && !allowedRunIds.has(resource.runId)) {
      throw new Error("Terminal resource append is outside the canonical producing/spawn run graph");
    }
  }
}

export function discardProducingJournalTurnForRunAttempt(
  store: AgentStore,
  input: DiscardProducingJournalTurnInput,
): ConversationTurn | null {
  return store.withTransaction(() => {
    const rows = store.allRows(
      `SELECT conversation_id, turn_id
       FROM conversation_turns
       WHERE producing_run_id = ? AND producing_attempt_id = ?
       ORDER BY conversation_id, turn_id`,
      [input.runId, input.attemptId],
    );
    if (rows.length === 0) return null;
    if (rows.length !== 1) throw new Error("Canonical run attempt is bound to multiple producing turns");
    return terminalizeJournalTurn(store, {
      ownerId: input.ownerId,
      conversationId: String(rows[0]!.conversation_id),
      turnId: String(rows[0]!.turn_id),
      producingRunId: input.runId,
      producingAttemptId: input.attemptId,
      disposition: "discard",
      nowMs: input.nowMs,
    });
  });
}

/**
 * Authenticated terminal mutation for runtime-produced turns. Callers provide
 * the exact canonical run/attempt proof and final material, while the kernel
 * alone derives success or failure from durable run state.
 */
export function terminalizeJournalTurn(
  store: AgentStore,
  input: TerminalizeJournalTurnInput,
): ConversationTurn {
  return terminalizeJournalTurnWithReceipt(store, input).turn;
}

export function terminalizeJournalTurnWithReceipt(
  store: AgentStore,
  input: TerminalizeJournalTurnInput,
): TerminalizeJournalTurnResult {
  const now = input.nowMs ?? Date.now();
  const producingRunId = nonEmpty(input.producingRunId, "producingRunId");
  const producingAttemptId = nonEmpty(input.producingAttemptId, "producingAttemptId");
  const contentBlocks = input.replaceContentBlocks === undefined
    ? undefined
    : validateContentBlocks(input.replaceContentBlocks);
  const resources = input.replaceResources === undefined
    ? undefined
    : validateResources(input.replaceResources);
  return store.withTransaction(() => {
    if (
      input.disposition === "discard"
      && (input.content !== undefined || contentBlocks !== undefined || resources !== undefined)
    ) {
      throw new Error("Discarded journal terminalization cannot apply late material");
    }
    assertConversationOwner(store, input.conversationId, input.ownerId);
    const authority = store.getOptionalRow(
      `SELECT r.status AS run_status, r.session_id, a.status AS attempt_status,
              (SELECT latest.attempt_id
               FROM run_attempts latest
               WHERE latest.run_id = r.run_id
               ORDER BY latest.attempt_no DESC
               LIMIT 1) AS latest_attempt_id
       FROM runs r
       JOIN sessions s ON s.session_id = r.session_id
       JOIN run_attempts a ON a.run_id = r.run_id AND a.attempt_id = ?
       WHERE r.run_id = ? AND s.owner_id = ?`,
      [producingAttemptId, producingRunId, input.ownerId],
    );
    if (!authority) throw new Error("Journal terminalization run or attempt is unknown or outside owner scope");
    if (String(authority.latest_attempt_id) !== producingAttemptId) {
      throw new Error("Journal terminalization requires the latest canonical run attempt");
    }
    if (!store.getOptionalRow(
      `SELECT 1 FROM surface_conversations
       WHERE conversation_id = ? AND owner_id = ? AND agent_session_id = ?
       LIMIT 1`,
      [input.conversationId, input.ownerId, String(authority.session_id)],
    )) {
      throw new Error("Journal terminalization run is not bound to the canonical conversation session");
    }
    const status = input.disposition === "discard"
      ? "failed"
      : journalTerminalStatus(authority.run_status, authority.attempt_status);
    const current = requireJournalTurn(store, input.conversationId, input.turnId);
    const existingCompletedRealExchange = firstCompletedRealExchange(store, input.conversationId);
    if (current.producingRunId !== producingRunId) {
      throw new Error("Journal terminalization run does not match the producing turn");
    }
    if (current.producingAttemptId !== producingAttemptId) {
      throw new Error("Journal terminalization attempt does not match the producing turn");
    }
    const content = input.content ?? current.content;
    const finalContentBlocks = input.disposition === "accept" && contentBlocks !== undefined
      ? monotonicAcceptContentBlocks(current.contentBlocks, contentBlocks)
      : contentBlocks ?? current.contentBlocks;
    const finalResources = input.disposition === "accept" && resources !== undefined
      ? monotonicAcceptResources(current.resources, resources)
      : resources ?? current.resources;
    const metadata = parseObjectJson(current.metadataJson) as Record<string, unknown>;
    const metadataJson = input.disposition === "discard"
      ? JSON.stringify({ ...metadata, terminalMarker: "discarded_terminal" })
      : current.metadataJson;
    const exactReplay = current.status === status
      && current.content === content
      && stableJson(current.contentBlocks) === stableJson(finalContentBlocks)
      && stableJson(current.resources) === stableJson(finalResources)
      && stableJson(parseObjectJson(current.metadataJson)) === stableJson(parseObjectJson(metadataJson));
    if (exactReplay) {
      return { turn: current, firstCompletedRealPair: false, firstCompletedRealExchange: null };
    }
    if (terminalTurnStatus(current.status) && current.producingAttemptId !== null) {
      throw new Error("Journal turn is already terminalized with different canonical material");
    }
    const terminalized = updateJournalTurnMutation(store, {
      ownerId: input.ownerId,
      conversationId: input.conversationId,
      turnId: input.turnId,
      status,
      content,
      replaceContentBlocks: finalContentBlocks,
      replaceResources: finalResources,
      producingRunId,
      producingAttemptId,
      metadataJson,
      nowMs: now,
    });
    const completedRealExchange = firstCompletedRealExchange(store, input.conversationId);
    const firstCompletedRealPair = existingCompletedRealExchange === null && completedRealExchange !== null;
    return {
      turn: terminalized,
      firstCompletedRealPair,
      firstCompletedRealExchange: firstCompletedRealPair ? completedRealExchange : null,
    };
  });
}

function firstCompletedRealExchange(
  store: AgentStore,
  conversationId: string,
): CompletedRealExchange | null {
  const usersByContinuityKey = new Map<string, string>();
  const rows = store.allRows(
    `SELECT role, content, metadata_json
     FROM conversation_turns
     WHERE conversation_id = ?
       AND status = 'completed'
       AND length(trim(content)) > 0
     ORDER BY turn_seq ASC`,
    [conversationId],
  );
  for (const row of rows) {
    const metadata = parseObjectJson(String(row.metadata_json ?? "{}")) as Record<string, unknown>;
    const continuityKey = typeof metadata.continuityKey === "string"
      ? metadata.continuityKey.trim()
      : "";
    if (!continuityKey) continue;
    const role = String(row.role);
    const content = String(row.content);
    if (role === "user") {
      if (!usersByContinuityKey.has(continuityKey)) {
        usersByContinuityKey.set(continuityKey, content);
      }
      continue;
    }
    if (role !== "assistant") continue;
    const userText = usersByContinuityKey.get(continuityKey);
    if (userText === undefined) continue;
    return { continuityKey, userText, assistantText: content };
  }
  return null;
}

function monotonicAcceptContentBlocks(
  current: readonly ConversationContentBlock[],
  incoming: readonly ConversationContentBlock[],
): ConversationContentBlock[] {
  const protectedCurrent = new Map(
    current
      .filter((block) => block.type === "agentSpawn" || block.type === "agentCompletion")
      .map((block) => [block.id, block] as const),
  );
  const result = incoming.map((block) => structuredClone(protectedCurrent.get(block.id) ?? block));
  const resultIds = new Set(result.map((block) => block.id));
  for (const block of protectedCurrent.values()) {
    if (!resultIds.has(block.id)) result.push(structuredClone(block));
  }
  return result;
}

function monotonicAcceptResources(
  current: readonly ConversationResource[],
  incoming: readonly ConversationResource[],
): ConversationResource[] {
  const currentById = new Map(current.map((resource) => [resource.id, resource] as const));
  const result = incoming.map((resource) => structuredClone(currentById.get(resource.id) ?? resource));
  const resultIds = new Set(result.map((resource) => resource.id));
  for (const resource of current) {
    if (!resultIds.has(resource.id)) result.push(structuredClone(resource));
  }
  return result;
}

/**
 * Atomically re-homes the current canonical turn graph into another owned
 * conversation. This is the migration boundary for surface consolidation:
 * callers must never copy `conversation_turns` directly because doing so
 * drops typed blocks/resources, revision visibility, delivery identity, and
 * the destination journal sequence.
 */
export function migrateJournalConversation(
  store: AgentStore,
  input: MigrateJournalConversationInput,
): MigrateJournalConversationResult {
  if (input.sourceConversationId === input.destinationConversationId) {
    return store.withTransaction(() => {
      assertConversationOwner(store, input.destinationConversationId, input.ownerId);
      const state = ensureJournalState(store, input.destinationConversationId, input.nowMs ?? Date.now());
      return {
        movedTurnCount: 0,
        movedRevisionCount: 0,
        destinationGeneration: state.generation,
        destinationHighWaterTurnSeq: state.highWaterTurnSeq,
      };
    });
  }
  const now = input.nowMs ?? Date.now();
  return store.withTransaction(() => {
    assertConversationOwner(store, input.sourceConversationId, input.ownerId);
    assertConversationOwner(store, input.destinationConversationId, input.ownerId);
    const sourceState = ensureJournalState(store, input.sourceConversationId, now);
    ensureJournalState(store, input.destinationConversationId, now);

    const sourceTurns = store.allRows(
      `SELECT ${TURN_COLUMNS}
       FROM conversation_turns
       WHERE conversation_id = ?
       ORDER BY turn_seq ASC, created_at_ms ASC, turn_id ASC`,
      [input.sourceConversationId],
    ).map(conversationTurnFromRow);
    if (sourceTurns.length === 0) {
      const destinationState = requireJournalState(store, input.destinationConversationId);
      return {
        movedTurnCount: 0,
        movedRevisionCount: 0,
        destinationGeneration: destinationState.generation,
        destinationHighWaterTurnSeq: destinationState.highWaterTurnSeq,
      };
    }

    assertJournalMigrationIdentityAvailable(store, input.destinationConversationId, sourceTurns);
    const sourceTurnIds = new Set(sourceTurns.map((turn) => turn.turnId));
    const revisionRows = store.allRows(
      `SELECT conversation_id, turn_seq, generation, turn_id, producer_id,
              mutation_kind, turn_json, payload_hash, created_at_ms
       FROM conversation_turn_revisions
       WHERE conversation_id = ? AND generation = ?
       ORDER BY turn_seq ASC`,
      [input.sourceConversationId, sourceState.generation],
    ).filter((row) => sourceTurnIds.has(String(row.turn_id)));
    const currentById = new Map(sourceTurns.map((turn) => [turn.turnId, turn]));
    const migratedRevisions: Array<{
      turn: ConversationTurn;
      mutationKind: "recorded" | "updated" | "imported";
      createdAtMs: number;
    }> = [];
    const migratedCurrentSequence = new Map<string, number>();
    for (const row of revisionRows) {
      const current = currentById.get(String(row.turn_id));
      if (!current) continue;
      const sequence = nextJournalSequence(store, input.destinationConversationId, now);
      const revision = migratedJournalRevisionTurn(row, current, input.destinationConversationId, sequence.turnSeq);
      migratedRevisions.push({
        turn: revision,
        mutationKind: journalMutationKind(row.mutation_kind),
        createdAtMs: Number(row.created_at_ms),
      });
      if (Number(row.turn_seq) === current.turnSeq) {
        migratedCurrentSequence.set(current.turnId, sequence.turnSeq);
      }
    }
    for (const current of sourceTurns) {
      if (migratedCurrentSequence.has(current.turnId)) continue;
      const sequence = nextJournalSequence(store, input.destinationConversationId, now);
      migratedRevisions.push({
        turn: {
          ...current,
          conversationId: input.destinationConversationId,
          turnSeq: sequence.turnSeq,
        },
        mutationKind: "imported",
        createdAtMs: now,
      });
      migratedCurrentSequence.set(current.turnId, sequence.turnSeq);
    }

    store.execute("DELETE FROM conversation_turns WHERE conversation_id = ?", [input.sourceConversationId]);
    store.execute(
      "DELETE FROM conversation_turn_revisions WHERE conversation_id = ? AND generation = ?",
      [input.sourceConversationId, sourceState.generation],
    );

    for (const source of sourceTurns) {
      const turnSeq = migratedCurrentSequence.get(source.turnId);
      if (turnSeq === undefined) throw new Error("Journal migration did not assign the current turn sequence");
      store.insertConversationTurn({
        conversationId: input.destinationConversationId,
        turnId: source.turnId,
        turnSeq,
        producerId: source.producerId,
        payloadHash: source.payloadHash,
        role: source.role,
        surfaceKind: source.surfaceKind,
        content: source.content,
        origin: source.origin,
        status: source.status,
        contentBlocks: source.contentBlocks,
        resources: source.resources,
        producingRunId: source.producingRunId,
        producingAttemptId: source.producingAttemptId,
        remoteId: source.remoteId,
        createdAtMs: source.createdAtMs,
        updatedAtMs: source.updatedAtMs,
        completedAtMs: source.completedAtMs,
        metadataJson: source.metadataJson,
      });
    }

    const destinationState = requireJournalState(store, input.destinationConversationId);
    for (const revision of migratedRevisions.sort((left, right) => left.turn.turnSeq - right.turn.turnSeq)) {
      appendJournalRevision(
        store,
        revision.turn,
        destinationState.generation,
        revision.mutationKind,
        revision.createdAtMs,
      );
    }
    return {
      movedTurnCount: sourceTurns.length,
      movedRevisionCount: migratedRevisions.length,
      destinationGeneration: destinationState.generation,
      destinationHighWaterTurnSeq: destinationState.highWaterTurnSeq,
    };
  });
}

export function listJournalTurns(
  store: AgentStore,
  input: {
    ownerId: string;
    conversationId: string;
    afterTurnSeq?: number;
    statuses?: readonly ConversationTurnStatus[];
    limit?: number;
  },
): JournalTurnRange {
  assertConversationOwner(store, input.conversationId, input.ownerId);
  const limit = boundedLimit(input.limit ?? 100);
  store.execute(
    `INSERT INTO conversation_journal_state(
       conversation_id, generation, high_water_turn_seq, updated_at_ms
     ) VALUES (?, 1, 0, ?)
     ON CONFLICT(conversation_id) DO NOTHING`,
    [input.conversationId, Date.now()],
  );
  const state = requireJournalState(store, input.conversationId);
  const values: unknown[] = [input.conversationId, input.afterTurnSeq ?? 0];
  let statusClause = "";
  if (input.statuses && input.statuses.length > 0) {
    statusClause = ` AND json_extract(turn_json, '$.status') IN (${input.statuses.map(() => "?").join(", ")})`;
    values.push(...input.statuses);
  }
  values.push(limit);
  const turns = store.allRows(
    `SELECT turn_json
     FROM conversation_turn_revisions
     WHERE conversation_id = ? AND generation = ${state.generation} AND turn_seq > ?${statusClause}
     ORDER BY turn_seq ASC
     LIMIT ?`,
    values,
  ).map((row) => JSON.parse(String(row.turn_json)) as ConversationTurn);
  return {
    conversationId: input.conversationId,
    generation: state.generation,
    generationBaseTurnSeq: state.generationBaseTurnSeq,
    highWaterTurnSeq: state.highWaterTurnSeq,
    turns,
  };
}

export function clearJournalConversation(
  store: AgentStore,
  input: {
    ownerId: string;
    conversationId: string;
    expectedGeneration: number;
    nowMs?: number;
  },
): {
  conversationId: string;
  generation: number;
  generationBaseTurnSeq: number;
  highWaterTurnSeq: number;
  deletedTurns: number;
} {
  if (!Number.isSafeInteger(input.expectedGeneration) || input.expectedGeneration < 1) {
    throw new Error("Journal clear expectedGeneration must be a positive integer");
  }
  const now = input.nowMs ?? Date.now();
  return store.withTransaction(() => {
    assertConversationOwner(store, input.conversationId, input.ownerId);
    store.execute(
      `INSERT INTO conversation_journal_state(
         conversation_id, generation, high_water_turn_seq, updated_at_ms
       ) VALUES (?, 1, 0, ?)
       ON CONFLICT(conversation_id) DO NOTHING`,
      [input.conversationId, now],
    );
    const current = requireJournalState(store, input.conversationId);
    if (input.expectedGeneration !== current.generation) {
      throw new Error("Journal clear generation is stale");
    }
    const generation = current.generation + 1;
    const highWaterTurnSeq = current.highWaterTurnSeq + 1;
    store.execute(
      `UPDATE conversation_journal_state
       SET generation = ?, generation_base_turn_seq = ?, high_water_turn_seq = ?, cleared_at_ms = ?, updated_at_ms = ?
       WHERE conversation_id = ?`,
      [generation, highWaterTurnSeq, highWaterTurnSeq, now, now, input.conversationId],
    );
    const deletedTurns = store.execute(
      "DELETE FROM conversation_turns WHERE conversation_id = ?",
      [input.conversationId],
    );
    return {
      conversationId: input.conversationId,
      generation,
      generationBaseTurnSeq: highWaterTurnSeq,
      highWaterTurnSeq,
      deletedTurns,
    };
  });
}

/** Project a canonical turn mutation to every surface bound to its conversation. */
export function journalTurnChangedWakes(
  store: AgentStore,
  ownerId: string,
  turn: ConversationTurn,
): JournalTurnChangedWake[] {
  assertConversationOwner(store, turn.conversationId, ownerId);
  const state = requireJournalState(store, turn.conversationId);
  const surfaces = store.allRows(
    `SELECT surface_kind, external_ref_kind, external_ref_id
     FROM surface_conversations
     WHERE owner_id = ? AND conversation_id = ?
     ORDER BY surface_kind ASC, external_ref_kind ASC, external_ref_id ASC`,
    [ownerId, turn.conversationId],
  );
  return surfaces.map((surface) => {
    const surfaceKind = String(surface.surface_kind);
    return {
      ownerId,
      conversationGeneration: state.generation,
      generationBaseTurnSeq: state.generationBaseTurnSeq,
      surfaceKind,
      externalRefKind: String(surface.external_ref_kind),
      externalRefId: String(surface.external_ref_id),
      // Swift treats this payload as a wake only, but its router keys from the
      // turn's surfaceKind. Project the binding surface so every wake routes.
      turn: journalTurnForSurfaceProjection(turn, surfaceKind),
    };
  });
}

/** State-only journal health. It intentionally never returns turn content. */
export function getJournalObservability(
  store: AgentStore,
  input: { ownerId?: string } = {},
): JournalObservabilitySnapshot {
  const ownerTurnClause = input.ownerId
    ? ` WHERE EXISTS (
          SELECT 1 FROM surface_conversations sc
          WHERE sc.conversation_id = conversation_turns.conversation_id AND sc.owner_id = ?
        )`
    : "";
  const turnRows = store.allRows(
    `SELECT status, COUNT(*) AS count FROM conversation_turns${ownerTurnClause} GROUP BY status`,
    input.ownerId ? [input.ownerId] : [],
  );
  return {
    turnStatusCounts: countRows<ConversationTurnStatus>(turnRows),
  };
}

function findJournalTurnById(store: AgentStore, turnId: string): ConversationTurn | null {
  const row = store.getOptionalRow(
    `SELECT ${TURN_COLUMNS} FROM conversation_turns WHERE turn_id = ? ORDER BY created_at_ms ASC LIMIT 1`,
    [turnId],
  );
  return row ? conversationTurnFromRow(row) : null;
}

function findJournalTurnByProducer(
  store: AgentStore,
  conversationId: string,
  producerId: string,
): ConversationTurn | null {
  const row = store.getOptionalRow(
    `SELECT ${TURN_COLUMNS}
     FROM conversation_turns
     WHERE conversation_id = ? AND producer_id = ?
     LIMIT 1`,
    [conversationId, producerId],
  );
  return row ? conversationTurnFromRow(row) : null;
}

function requireJournalTurn(store: AgentStore, conversationId: string, turnId: string): ConversationTurn {
  const row = store.getOptionalRow(
    `SELECT ${TURN_COLUMNS}
     FROM conversation_turns WHERE conversation_id = ? AND turn_id = ?`,
    [conversationId, turnId],
  );
  if (!row) throw new Error(`Unknown journal turn ${turnId}`);
  return conversationTurnFromRow(row);
}

function assertConversationOwner(store: AgentStore, conversationId: string, ownerId: string): void {
  const row = store.getOptionalRow(
    `SELECT 1 FROM surface_conversations WHERE conversation_id = ? AND owner_id = ? LIMIT 1`,
    [conversationId, ownerId],
  );
  if (!row) throw new Error("Journal conversation is outside owner scope");
}

function assertProducingJournalTurnMapping(
  store: AgentStore,
  input: ProducingJournalTurnAdmissionInput,
): void {
  assertConversationOwner(store, input.conversationId, input.ownerId);
  const mapping = store.getOptionalRow(
    `SELECT 1 FROM surface_conversations
     WHERE conversation_id = ? AND owner_id = ? AND agent_session_id = ?
     LIMIT 1`,
    [input.conversationId, input.ownerId, input.sessionId],
  );
  if (!mapping) {
    throw new Error("Producing turn admission requires the exact canonical owner/session/conversation mapping");
  }
}

function assertProducingRunOwner(store: AgentStore, runId: string | null, ownerId: string): void {
  if (runId === null) return;
  const row = store.getOptionalRow(
    `SELECT 1
     FROM runs r JOIN sessions s ON s.session_id = r.session_id
     WHERE r.run_id = ? AND s.owner_id = ?`,
    [runId, ownerId],
  );
  if (!row) throw new Error("Producing run is outside owner scope");
}

function assertIdempotentRecord(
  existing: ConversationTurn,
  input: RecordJournalTurnInput & {
    turnId: string;
    contentBlocks: ConversationContentBlock[];
    resources: ConversationResource[];
    metadataJson: string;
    producerId: string;
  },
): void {
  if (existing.conversationId !== input.conversationId) {
    throw new Error("Canonical turn ID belongs to a different conversation");
  }
  const equivalent = existing.role === input.role
    && existing.surfaceKind === input.surfaceKind
    && existing.content === input.content
    && existing.origin === input.origin
    && existing.producerId === input.producerId
    && existing.producingRunId === (input.producingRunId ?? null)
    && existing.producingAttemptId === (input.producingAttemptId ?? null)
    && stableJson(existing.contentBlocks) === stableJson(input.contentBlocks)
    && stableJson(existing.resources) === stableJson(input.resources)
    && stableJson(parseObjectJson(existing.metadataJson)) === stableJson(parseObjectJson(input.metadataJson));
  if (!equivalent) throw new Error("Canonical turn or producer identity collision has different journal content");
}

function validateContentBlocks(blocks: readonly ConversationContentBlock[]): ConversationContentBlock[] {
  const ids = new Set<string>();
  return blocks.map((block) => {
    const id = nonEmpty(block.id, "content block id");
    nonEmpty(block.type, "content block type");
    if (ids.has(id)) throw new Error(`Duplicate content block ID ${id}`);
    ids.add(id);
    return structuredClone(block);
  });
}

function validateResources(resources: readonly ConversationResource[]): ConversationResource[] {
  const ids = new Set<string>();
  return resources.map((resource) => {
    const id = nonEmpty(resource.id, "resource id");
    nonEmpty(resource.title, "resource title");
    if (ids.has(id)) throw new Error(`Duplicate resource ID ${id}`);
    ids.add(id);
    return structuredClone(resource);
  });
}

function mergeById<T extends { id: string }>(current: readonly T[], updates: readonly T[]): T[] {
  const result = current.map((value) => structuredClone(value));
  const indexes = new Map(result.map((value, index) => [value.id, index]));
  for (const value of updates) {
    const index = indexes.get(value.id);
    if (index === undefined) {
      indexes.set(value.id, result.length);
      result.push(structuredClone(value));
    } else {
      result[index] = structuredClone(value);
    }
  }
  return result;
}

function assertTurnStatusTransition(from: ConversationTurnStatus, to: ConversationTurnStatus): void {
  const allowed: Record<ConversationTurnStatus, readonly ConversationTurnStatus[]> = {
    pending: ["pending", "streaming", "completed", "failed"],
    streaming: ["streaming", "completed", "failed"],
    completed: ["completed"],
    failed: ["failed"],
  };
  if (!allowed[from].includes(to)) throw new Error(`Invalid journal turn status transition ${from} -> ${to}`);
}

function terminalTurnStatus(status: ConversationTurnStatus): boolean {
  return status === "completed" || status === "failed";
}

function journalTerminalStatus(runStatus: unknown, attemptStatus: unknown): ConversationTurnStatus {
  const terminal = new Set(["succeeded", "failed", "cancelled", "timed_out", "orphaned"]);
  const run = String(runStatus);
  const attempt = String(attemptStatus);
  if (!terminal.has(run) || !terminal.has(attempt)) {
    throw new Error("Journal terminalization requires a terminal canonical run and attempt");
  }
  if ((run === "succeeded") !== (attempt === "succeeded")) {
    throw new Error("Journal terminalization run and attempt outcomes disagree");
  }
  return run === "succeeded" ? "completed" : "failed";
}

function boundedLimit(limit: number): number {
  if (!Number.isInteger(limit) || limit <= 0) throw new Error("Journal list limit must be a positive integer");
  return Math.min(limit, MAX_LIST_BATCH);
}

function validObjectJson(raw: string, field: string): string {
  const parsed = parseObjectJson(raw);
  if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new Error(`${field} must contain a JSON object`);
  }
  return JSON.stringify(parsed);
}

function parseObjectJson(raw: string): unknown {
  try {
    return JSON.parse(raw) as unknown;
  } catch {
    throw new Error("Journal metadata must be valid JSON");
  }
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${stableJson(object[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function sha256(value: string): string {
  return `sha256:${createHash("sha256").update(value).digest("hex")}`;
}

function journalTurnPayloadHash(value: Record<string, unknown>): string {
  return sha256(stableJson(value));
}

function nextJournalSequence(
  store: AgentStore,
  conversationId: string,
  nowMs: number,
): { generation: number; turnSeq: number } {
  store.execute(
    `INSERT INTO conversation_journal_state(
       conversation_id, generation, high_water_turn_seq, updated_at_ms
     ) VALUES (?, 1, 1, ?)
     ON CONFLICT(conversation_id) DO UPDATE SET
       high_water_turn_seq = conversation_journal_state.high_water_turn_seq + 1,
       updated_at_ms = excluded.updated_at_ms`,
    [conversationId, nowMs],
  );
  const state = requireJournalState(store, conversationId);
  return { generation: state.generation, turnSeq: state.highWaterTurnSeq };
}

function ensureJournalState(
  store: AgentStore,
  conversationId: string,
  nowMs: number,
): { generation: number; generationBaseTurnSeq: number; highWaterTurnSeq: number } {
  store.execute(
    `INSERT INTO conversation_journal_state(
       conversation_id, generation, high_water_turn_seq, updated_at_ms
     ) SELECT ?, 1, COALESCE(MAX(turn_seq), 0), ?
       FROM conversation_turns WHERE conversation_id = ?
     ON CONFLICT(conversation_id) DO NOTHING`,
    [conversationId, nowMs, conversationId],
  );
  return requireJournalState(store, conversationId);
}

function assertJournalMigrationIdentityAvailable(
  store: AgentStore,
  destinationConversationId: string,
  sourceTurns: readonly ConversationTurn[],
): void {
  for (const turn of sourceTurns) {
    if (store.getOptionalRow(
      "SELECT 1 FROM conversation_turns WHERE conversation_id = ? AND turn_id = ?",
      [destinationConversationId, turn.turnId],
    )) {
      throw new Error(`Journal migration turn identity collision: ${turn.turnId}`);
    }
    if (store.getOptionalRow(
      "SELECT 1 FROM conversation_turns WHERE conversation_id = ? AND producer_id = ?",
      [destinationConversationId, turn.producerId],
    )) {
      throw new Error(`Journal migration producer identity collision: ${turn.producerId}`);
    }
    if (turn.remoteId && store.getOptionalRow(
      "SELECT 1 FROM conversation_turns WHERE conversation_id = ? AND remote_id = ?",
      [destinationConversationId, turn.remoteId],
    )) {
      throw new Error(`Journal migration remote identity collision: ${turn.remoteId}`);
    }
  }
}

function journalMutationKind(value: unknown): "recorded" | "updated" | "imported" {
  if (value === "recorded" || value === "updated" || value === "imported") return value;
  throw new Error("Journal migration encountered an invalid revision mutation kind");
}

function migratedJournalRevisionTurn(
  row: Record<string, unknown>,
  current: ConversationTurn,
  destinationConversationId: string,
  destinationTurnSeq: number,
): ConversationTurn {
  let parsed: Record<string, unknown>;
  try {
    const candidate = JSON.parse(String(row.turn_json)) as unknown;
    if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) throw new Error("not an object");
    parsed = candidate as Record<string, unknown>;
  } catch {
    throw new Error(`Journal migration encountered an invalid revision for ${current.turnId}`);
  }
  if (String(parsed.turnId ?? current.turnId) !== current.turnId) {
    throw new Error("Journal migration revision turn identity does not match its current turn");
  }
  const role = parsed.role ?? current.role;
  if (role !== "user" && role !== "assistant") throw new Error("Journal migration revision has an invalid role");
  const status = parsed.status ?? current.status;
  if (status !== "pending" && status !== "streaming" && status !== "completed" && status !== "failed") {
    throw new Error("Journal migration revision has an invalid status");
  }
  const contentBlocks = validateContentBlocks(
    Array.isArray(parsed.contentBlocks) ? parsed.contentBlocks as ConversationContentBlock[] : current.contentBlocks,
  );
  const resources = validateResources(
    Array.isArray(parsed.resources) ? parsed.resources as ConversationResource[] : current.resources,
  );
  const metadataJson = validObjectJson(String(parsed.metadataJson ?? current.metadataJson), "metadataJson");
  return {
    conversationId: destinationConversationId,
    turnId: current.turnId,
    turnSeq: destinationTurnSeq,
    producerId: String(parsed.producerId ?? row.producer_id ?? current.producerId),
    payloadHash: String(parsed.payloadHash ?? row.payload_hash ?? current.payloadHash),
    role,
    surfaceKind: String(parsed.surfaceKind ?? current.surfaceKind),
    content: String(parsed.content ?? current.content),
    origin: (parsed.origin ?? current.origin) as ConversationTurnOrigin,
    status,
    contentBlocks,
    resources,
    producingRunId: parsed.producingRunId === undefined
      ? current.producingRunId
      : parsed.producingRunId == null ? null : String(parsed.producingRunId),
    producingAttemptId: parsed.producingAttemptId === undefined
      ? current.producingAttemptId
      : parsed.producingAttemptId == null ? null : String(parsed.producingAttemptId),
    remoteId: parsed.remoteId === undefined
      ? current.remoteId
      : parsed.remoteId == null ? null : String(parsed.remoteId),
    createdAtMs: Number(parsed.createdAtMs ?? current.createdAtMs),
    updatedAtMs: Number(parsed.updatedAtMs ?? current.updatedAtMs),
    completedAtMs: parsed.completedAtMs === undefined
      ? current.completedAtMs
      : parsed.completedAtMs == null ? null : Number(parsed.completedAtMs),
    metadataJson,
  };
}

function requireJournalState(
  store: AgentStore,
  conversationId: string,
): { generation: number; generationBaseTurnSeq: number; highWaterTurnSeq: number } {
  const row = store.getRow(
    `SELECT generation, generation_base_turn_seq, high_water_turn_seq
     FROM conversation_journal_state WHERE conversation_id = ?`,
    [conversationId],
  );
  return {
    generation: Number(row.generation),
    generationBaseTurnSeq: Number(row.generation_base_turn_seq ?? 0),
    highWaterTurnSeq: Number(row.high_water_turn_seq),
  };
}

function appendJournalRevision(
  store: AgentStore,
  turn: ConversationTurn,
  generation: number,
  mutationKind: "recorded" | "updated" | "imported",
  nowMs: number,
): void {
  store.execute(
    `INSERT INTO conversation_turn_revisions(
       conversation_id, turn_seq, generation, turn_id, producer_id,
       mutation_kind, turn_json, payload_hash, created_at_ms
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      turn.conversationId,
      turn.turnSeq,
      generation,
      turn.turnId,
      turn.producerId,
      mutationKind,
      JSON.stringify(turn),
      turn.payloadHash,
      nowMs,
    ],
  );
}

function nonEmpty(value: string, field: string): string {
  const trimmed = value.trim();
  if (!trimmed) throw new Error(`${field} must not be empty`);
  return trimmed;
}

function countRows<T extends string>(rows: Record<string, unknown>[]): Partial<Record<T, number>> {
  const result: Partial<Record<T, number>> = {};
  for (const row of rows) result[String(row.status) as T] = Number(row.count);
  return result;
}
