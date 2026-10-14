import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, it } from "vitest";
import { ConversationStorage } from "../src/conversation-storage.js";

const directories: string[] = [];
afterEach(() => {
  for (const path of directories.splice(0)) rmSync(path, { recursive: true, force: true });
});

it("keeps accepted conversation history across restart without an agent runtime", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-conversation-storage-"));
  directories.push(stateDir);
  const surface = { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "reading" };
  const first = new ConversationStorage({ stateDir, ownerId: "reader" });
  first.createChat({ chatId: "reading", title: "Reading together" });
  const recorded = first.recordExchange(surface, [{
    turnId: "utterance-1", role: "user", origin: "typed_chat", status: "completed",
    content: "Help me start reading.", contentBlocks: [], createdAtMs: 100,
  }], 1);
  expect(recorded.turns[0]).toMatchObject({ turnId: "utterance-1", turnSeq: 1 });
  first.close();

  const reopened = new ConversationStorage({ stateDir, ownerId: "reader" });
  expect(reopened.listChats()).toMatchObject([{
    chatId: "reading", title: "Reading together", messageCount: 1,
    preview: "Help me start reading.",
  }]);
  expect(reopened.listTurns({ ...surface, surfaceKind: "realtime_voice" }).turns)
    .toMatchObject([{ turnId: "utterance-1", content: "Help me start reading." }]);
  reopened.close();
});

it("finalizes a streamed answer once and keeps interrupted delivery separate from saved text", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-conversation-stream-"));
  directories.push(stateDir);
  const storage = new ConversationStorage({ stateDir, ownerId: "reader" });
  const surface = { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "default" };
  const answer = {
    turnId: "answer-1", role: "assistant" as const, origin: "realtime_voice" as const,
    status: "streaming" as const, content: "", contentBlocks: [], createdAtMs: 100,
  };
  storage.recordExchange(surface, [answer], 1);
  storage.recordExchange(surface, [answer], 1);
  storage.updateTurn(surface, {
    turnId: "answer-1", status: "completed", content: "Try one paragraph",
    metadataJson: '{"voiceDeliveryOutcome":"interrupted"}',
  }, 1);
  const turns = storage.listTurns(surface).turns;
  expect(turns.at(-1)).toMatchObject({
    turnId: "answer-1", status: "completed", content: "Try one paragraph",
    metadataJson: '{"voiceDeliveryOutcome":"interrupted"}',
  }, 1);
  expect(storage.listChats()[0].messageCount).toBe(1);
  storage.close();
});

it("keeps catalog edits and deletion isolated to the current owner", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-conversation-owners-"));
  directories.push(stateDir);
  const a = new ConversationStorage({ stateDir, ownerId: "owner-a" });
  const b = new ConversationStorage({ stateDir, ownerId: "owner-b" });
  a.createChat({ chatId: "shared-name", title: "A private chat" });
  b.createChat({ chatId: "shared-name", title: "B private chat" });
  a.updateChat({ chatId: "shared-name", title: "A renamed", starred: true });
  expect(a.listChats()).toMatchObject([{ title: "A renamed", starred: true }]);
  expect(b.listChats()).toMatchObject([{ title: "B private chat", starred: false }]);
  a.deleteChat("shared-name");
  expect(a.listChats()).toEqual([]);
  expect(b.listChats()).toMatchObject([{ title: "B private chat" }]);
  expect(() => a.listTurns({ surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "shared-name" }))
    .toThrow("chat_catalog_not_found");
  a.close(); b.close();
});

it("fences delayed writes after clear, including a conversation that was empty", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-conversation-generation-"));
  directories.push(stateDir);
  const storage = new ConversationStorage({ stateDir, ownerId: "reader" });
  const surface = { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "default" };
  const empty = storage.listTurns(surface);
  expect(empty.generation).toBe(1);
  expect(storage.clear(surface, empty.generation).generation).toBe(2);
  const turn = { turnId: "delayed", role: "user" as const, origin: "typed_chat" as const, status: "completed" as const, content: "Old answer", contentBlocks: [] };
  expect(() => storage.recordExchange(surface, [turn], empty.generation)).toThrow("stale");
  expect(storage.listTurns(surface).turns).toEqual([]);
  storage.recordExchange(surface, [{ ...turn, turnId: "current" }], 2);
  expect(storage.listTurns(surface).turns).toMatchObject([{ turnId: "current" }]);
  storage.close();
});

it("revises accepted voice partials at stable IDs and never duplicates the completed exchange", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-conversation-revisions-"));
  directories.push(stateDir);
  const storage = new ConversationStorage({ stateDir, ownerId: "reader" });
  const surface = { surfaceKind: "realtime_voice", externalRefKind: "chat", externalRefId: "default" };
  const partial = { turnId: "heard", role: "user" as const, origin: "realtime_voice" as const, status: "streaming" as const, content: "I need", contentBlocks: [], metadataJson: '{"continuityKey":"voice-1"}' };
  storage.recordOrReviseExchange(surface, [partial, { ...partial, turnId: "spoken", role: "assistant", content: "" }], 1);
  storage.recordOrReviseExchange(surface, [{ ...partial, status: "completed", content: "I need help." }], 1);
  const final = { ...partial, turnId: "spoken", role: "assistant" as const, status: "completed" as const, content: "One step at a time." };
  expect(storage.recordOrReviseExchange(surface, [final], 1).firstCompletedRealPair).toBe(true);
  expect(storage.recordOrReviseExchange(surface, [final], 1).firstCompletedRealPair).toBe(false);
  expect(storage.listChats()[0].messageCount).toBe(2);
  expect(() => storage.recordOrReviseExchange(surface, [{ ...partial, content: "late partial" }], 1)).toThrow();
  storage.close();
});

it("repairs interrupted history after restart without ending a currently streaming exchange", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-conversation-repair-")); directories.push(stateDir);
  const surface = { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "default" };
  const first = new ConversationStorage({ stateDir, ownerId: "reader" });
  first.recordExchange(surface, [{ turnId: "active", role: "assistant", origin: "typed_chat", status: "streaming", content: "Partial", contentBlocks: [] }], 1);
  expect(first.repair(surface, ["active"], 1)).toEqual([]);
  first.close();
  const reopened = new ConversationStorage({ stateDir, ownerId: "reader" });
  expect(reopened.repair(surface, ["active"], 1)).toMatchObject([{ turnId: "active", status: "failed", content: "Partial" }]);
  reopened.close();
});

it("bounds context by logical turns instead of partial revisions and preserves original order", () => {
  const stateDir = mkdtempSync(join(tmpdir(), "intentive-conversation-tail-")); directories.push(stateDir);
  const storage = new ConversationStorage({ stateDir, ownerId: "reader" });
  const surface = { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "default" };
  const base = { role: "assistant" as const, origin: "realtime_voice" as const, status: "streaming" as const, contentBlocks: [], createdAtMs: 1 };
  for (let index = 1; index <= 4; index++) storage.recordExchange(surface, [{ ...base, turnId: `turn-${index}`, content: `earlier ${index}` }], 1);
  for (let revision = 0; revision < 40; revision++) storage.recordOrReviseExchange(surface, [{ ...base, turnId: "turn-4", content: `partial ${revision}` }], 1);
  // Even a late revision of an earlier turn must retain that turn's position.
  storage.recordOrReviseExchange(surface, [{ ...base, turnId: "turn-2", content: "earlier revised" }], 1);
  const result = storage.tailTurns(surface, 3);
  expect(result.turns.map((turn) => [turn.turnId, turn.content])).toEqual([
    ["turn-2", "earlier revised"], ["turn-3", "earlier 3"], ["turn-4", "partial 39"],
  ]);
  expect(result.generation).toBe(1);
  storage.clear(surface, 1);
  expect(storage.tailTurns(surface, 3)).toMatchObject({ generation: 2, turns: [] });
  storage.close();
});
