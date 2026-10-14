import { z } from "zod";
import { ConversationStorage } from "./conversation-storage.js";
import type { ConversationTurn } from "./runtime/types.js";
import type { JournalTurnChangedWake } from "./runtime/conversation-journal.js";

const id = z.string().trim().min(1).max(256);
const text = z.string().max(100_000);
const envelope = {
  protocolVersion: z.literal(2), requestId: id, clientId: id, ownerId: id,
};
const surface = {
  surfaceKind: z.enum(["main_chat", "floating_chat", "realtime_voice", "realtime", "onboarding"]),
  externalRefKind: z.enum(["chat", "session"]), externalRefId: id,
};
const generation = z.number().int().positive();
const status = z.enum(["pending", "streaming", "completed", "failed"]);
const block = z.object({ type: z.enum(["text", "thinking"]), id, text }).strict();
const resource = z.object({
  id, title: text, origin: z.enum(["userAttachment", "generatedArtifact"]),
  state: z.union([z.enum(["uploading", "ready", "retained", "opened", "dismissed"]), z.custom<`failed:${string}`>((value) => typeof value === "string" && value.startsWith("failed:") && value.length <= 100_000)]),
  subtitle: text.optional(), mimeType: z.string().max(256).optional(),
  thumbnailURL: text.optional(), uri: text.optional(), artifactId: id.optional(),
  sessionId: id.optional(), runId: id.optional(),
}).strict();
const write = z.object({
  turnId: id, role: z.enum(["user", "assistant"]),
  origin: z.enum(["typed_chat", "floating_chat", "realtime_voice", "notification", "swift_backfill", "legacy"]),
  status, content: text, contentBlocks: z.array(block).max(100),
  resources: z.array(resource).max(100).optional(), metadataJson: text.optional(),
  createdAtMs: z.number().int().nonnegative().optional(),
}).strict();
const update = z.object({
  turnId: id, status: status.optional(), content: text.optional(),
  replaceContentBlocks: z.array(block).max(100).optional(), appendContentBlocks: z.array(block).max(100).optional(),
  replaceResources: z.array(resource).max(100).optional(), appendResources: z.array(resource).max(100).optional(),
  metadataJson: text.optional(),
}).strict();
const request = z.discriminatedUnion("type", [
  z.object({ ...envelope, type: z.literal("chat_catalog_list") }).strict(),
  z.object({ ...envelope, type: z.literal("chat_catalog_create"), chatId: id, title: text.optional() }).strict(),
  z.object({ ...envelope, type: z.literal("chat_catalog_update"), chatId: id, title: text.optional(), titleOrigin: z.enum(["automatic", "manual"]).optional(), expectedTitleOrigin: z.enum(["default", "automatic", "manual"]).optional(), starred: z.boolean().optional() }).strict(),
  z.object({ ...envelope, type: z.literal("chat_catalog_delete"), chatId: id }).strict(),
  z.object({ ...envelope, ...surface, type: z.literal("resolve_surface_session") }).strict(),
  z.object({ ...envelope, ...surface, type: z.literal("journal_tail_turns"), limit: z.number().int().min(1).max(100).default(8) }).strict(),
  z.object({ ...envelope, ...surface, type: z.literal("journal_list_turns"), afterTurnSeq: z.number().int().nonnegative().default(0), limit: z.number().int().min(1).max(100).default(100) }).strict(),
  z.object({ ...envelope, ...surface, type: z.enum(["journal_record_exchange", "journal_revise_exchange"]), expectedGeneration: generation, turns: z.array(write).min(1).max(2) }).strict(),
  z.object({ ...envelope, ...surface, type: z.literal("journal_update_turn"), expectedGeneration: generation, update }).strict(),
  z.object({ ...envelope, ...surface, type: z.literal("journal_clear_turns"), expectedGeneration: generation }).strict(),
  z.object({ ...envelope, ...surface, type: z.literal("journal_repair_turns"), expectedGeneration: generation, turnIds: z.array(id).max(100) }).strict(),
]);

/** A bounded storage protocol. No credentials, model requests, worker or tool methods. */
export function dispatchConversationRequest(storage: ConversationStorage, input: unknown): Record<string, unknown> & { wakes?: JournalTurnChangedWake[] } {
  const parsed = request.parse(input);
  if (parsed.ownerId !== storage.ownerId) throw new Error("conversation_owner_mismatch");
  if ("surfaceKind" in parsed && (parsed.surfaceKind === "onboarding"
    ? parsed.externalRefKind !== "session" || parsed.externalRefId !== "default"
    : parsed.externalRefKind !== "chat")) throw new Error("invalid_conversation_surface");
  const common = { protocolVersion: 2, requestId: parsed.requestId, clientId: parsed.clientId, ownerId: storage.ownerId, ok: true };
  switch (parsed.type) {
    case "chat_catalog_list": return { ...common, type: "chat_catalog_result", operation: "list", chats: storage.listChats(), retainedAttachmentUris: storage.retainedAttachmentUris(storage.ownerId) };
    case "chat_catalog_create": return { ...common, type: "chat_catalog_result", operation: "create", chat: storage.createChat(parsed) };
    case "chat_catalog_update": return { ...common, type: "chat_catalog_result", operation: "update", chat: storage.updateChat(parsed) };
    case "chat_catalog_delete": return { ...common, type: "chat_catalog_result", operation: "delete", ...storage.deleteChat(parsed.chatId) };
    case "resolve_surface_session": {
      const resolved = storage.resolveSurface(parsed);
      return { ...common, type: "surface_session_resolved", created: false, conversationId: resolved.conversationId, sessionId: resolved.agentSessionId };
    }
  }
  let result: Record<string, unknown> = {};
  let changed: ConversationTurn[] = [];
  let operation: string;
  switch (parsed.type) {
    case "journal_list_turns": operation = "list"; break;
    case "journal_tail_turns": operation = "tail"; break;
    case "journal_record_exchange":
      operation = "record_exchange";
      { const receipt = storage.recordExchange(parsed, parsed.turns, parsed.expectedGeneration); result = { ...receipt }; changed = receipt.turns; } break;
    case "journal_revise_exchange":
      operation = "record_exchange";
      { const receipt = storage.recordOrReviseExchange(parsed, parsed.turns, parsed.expectedGeneration); result = { ...receipt }; changed = receipt.turns; } break;
    case "journal_update_turn":
      operation = "update";
      { const receipt = storage.updateTurn(parsed, parsed.update, parsed.expectedGeneration); result = { ...receipt }; changed = [receipt.turn]; } break;
    case "journal_clear_turns": {
      operation = "clear";
      const clear = storage.clear(parsed, parsed.expectedGeneration);
      result = { clearedCount: clear.deletedTurns }; break;
    }
    case "journal_repair_turns":
      operation = "repair";
      changed = storage.repair(parsed, parsed.turnIds, parsed.expectedGeneration); result = { turns: changed }; break;
  }
  const range = parsed.type === "journal_tail_turns" ? storage.tailTurns(parsed, parsed.limit) : storage.listTurns(parsed, parsed.type === "journal_list_turns" ? parsed.afterTurnSeq : 0, parsed.type === "journal_list_turns" ? parsed.limit : 1);
  return {
    ...common, type: "journal_operation_result", operation,
    surfaceKind: parsed.surfaceKind, externalRefKind: parsed.externalRefKind, externalRefId: parsed.externalRefId,
    conversationId: range.conversationId, conversationGeneration: range.generation,
    generationBaseTurnSeq: range.generationBaseTurnSeq, highWaterTurnSeq: range.highWaterTurnSeq,
    turns: parsed.type === "journal_list_turns" || parsed.type === "journal_tail_turns" ? range.turns : [], ...result,
    wakes: storage.wakes(changed),
  };
}
