import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { AdapterRegistry } from "../src/runtime/adapter-registry.js";
import { AgentRuntimeKernel } from "../src/runtime/kernel-coordinator.js";
import { recordJournalExchange } from "../src/runtime/conversation-journal.js";
import { SqliteAgentStore } from "../src/runtime/sqlite-store.js";

const createdDirs: string[] = [];

afterEach(() => {
  for (const dir of createdDirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function makeKernel(nowMs = 1) {
  const stateDir = mkdtempSync(join(tmpdir(), "omi-chat-catalog-"));
  createdDirs.push(stateDir);
  const store = new SqliteAgentStore({ stateDir, reconcileOnOpen: false, nowMs: () => nowMs });
  return {
    store,
    kernel: new AgentRuntimeKernel({ store, registry: new AdapterRegistry() }),
  };
}

describe("local Chat catalog", () => {
  it("creates and lists owner-scoped chats from the existing session and journal authority", () => {
    const { kernel, store } = makeKernel();
    const created = kernel.createChatCatalog({
      ownerId: "owner-a",
      chatId: "chat-a",
      defaultAdapterId: "pi-mono",
      modelProfile: "gemini-3.7-flash",
      defaultCwd: "/tmp/artifacts",
    });
    const conversationId = String(store.getRow(
      `SELECT conversation_id FROM surface_conversations
       WHERE owner_id = ? AND surface_kind = 'main_chat' AND external_ref_id = ?`,
      ["owner-a", "chat-a"],
    ).conversation_id);
    recordJournalExchange(store, {
      ownerId: "owner-a",
      conversationId,
      turns: [
        {
          turnId: "turn-user-a",
          role: "user",
          surfaceKind: "main_chat",
          origin: "typed_chat",
          status: "completed",
          content: "What did I decide today?",
          contentBlocks: [],
        },
        {
          turnId: "turn-assistant-a",
          role: "assistant",
          surfaceKind: "main_chat",
          origin: "typed_chat",
          status: "completed",
          content: "You decided to keep Chat local.",
          contentBlocks: [],
        },
      ],
    });

    expect(created).toMatchObject({
      chatId: "chat-a",
      title: "New Chat",
      titleOrigin: "default",
      starred: false,
    });
    expect(kernel.listChatCatalog({ ownerId: "owner-a" })).toMatchObject([
      {
        chatId: "chat-a",
        preview: "You decided to keep Chat local.",
        messageCount: 2,
      },
    ]);
    expect(kernel.listChatCatalog({ ownerId: "owner-b" })).toEqual([]);
  });

  it("makes create idempotent and protects manual titles across owner-scoped updates and deletes", () => {
    const { kernel, store } = makeKernel();
    const input = {
      ownerId: "owner-a",
      chatId: "chat-a",
      defaultAdapterId: "pi-mono",
      modelProfile: "gemini-3.7-flash",
      defaultCwd: "/tmp/artifacts",
    };
    kernel.createChatCatalog(input);
    kernel.createChatCatalog(input);
    const conversationId = String(store.getRow(
      "SELECT conversation_id FROM surface_conversations WHERE owner_id = ? AND external_ref_id = ?",
      ["owner-a", "chat-a"],
    ).conversation_id);
    recordJournalExchange(store, {
      ownerId: "owner-a",
      conversationId,
      turns: [{
        turnId: "turn-a",
        role: "user",
        surfaceKind: "main_chat",
        origin: "typed_chat",
        status: "completed",
        content: "Delete this atomically",
        contentBlocks: [],
      }],
    });
    expect(store.getRow(
      "SELECT COUNT(*) AS count FROM sessions WHERE owner_id = ? AND external_ref_id = ?",
      ["owner-a", "chat-a"],
    ).count).toBe(1);

    expect(kernel.updateChatCatalog({
      ownerId: "owner-a",
      chatId: "chat-a",
      title: "One Two Three Four Five Six Seven",
      titleOrigin: "automatic",
      expectedTitleOrigin: "default",
      starred: true,
    })).toMatchObject({ title: "One Two Three Four Five Six", titleOrigin: "automatic", starred: true });
    expect(kernel.updateChatCatalog({
      ownerId: "owner-a",
      chatId: "chat-a",
      title: "My decision log",
      titleOrigin: "manual",
    })).toMatchObject({ title: "My decision log", titleOrigin: "manual" });
    expect(kernel.updateChatCatalog({
      ownerId: "owner-a",
      chatId: "chat-a",
      title: "Late automatic title",
      titleOrigin: "automatic",
      expectedTitleOrigin: "default",
    })).toMatchObject({ title: "My decision log", titleOrigin: "manual" });

    kernel.createChatCatalog({ ...input, ownerId: "owner-b" });
    expect(() => kernel.deleteChatCatalog({ ownerId: "owner-b", chatId: "default" }))
      .toThrow(/default_chat_cannot_be_deleted/);
    expect(kernel.deleteChatCatalog({ ownerId: "owner-a", chatId: "chat-a" }))
      .toEqual({ deletedChatId: "chat-a", retainedAttachmentUris: [] });
    expect(() => kernel.resolveExistingSurfaceSession({
      ownerId: "owner-a",
      surfaceRef: { surfaceKind: "main_chat", externalRefKind: "chat", externalRefId: "chat-a" },
    })).toThrow(/chat_catalog_not_found/);
    expect(kernel.deleteChatCatalog({ ownerId: "owner-a", chatId: "chat-a" }))
      .toEqual({ deletedChatId: "chat-a", retainedAttachmentUris: [] });
    expect(store.getRow(
      "SELECT COUNT(*) AS count FROM conversation_turns WHERE conversation_id = ?",
      [conversationId],
    ).count).toBe(0);
    expect(kernel.listChatCatalog({ ownerId: "owner-a" })).toEqual([]);
    expect(kernel.listChatCatalog({ ownerId: "owner-b" })).toHaveLength(1);
  });

  it("orders the catalog by derived completed-turn activity", () => {
    const { kernel, store } = makeKernel();
    const create = (chatId: string) => kernel.createChatCatalog({
      ownerId: "owner-a",
      chatId,
      defaultAdapterId: "pi-mono",
      modelProfile: "gemini-3.7-flash",
      defaultCwd: "/tmp/artifacts",
    });
    create("chat-with-newest-turn");
    create("chat-with-newer-session-row");
    store.execute(
      "UPDATE sessions SET last_activity_at_ms = 5000 WHERE owner_id = ? AND external_ref_id = ?",
      ["owner-a", "chat-with-newer-session-row"],
    );
    const conversationId = String(store.getRow(
      "SELECT conversation_id FROM surface_conversations WHERE owner_id = ? AND external_ref_id = ?",
      ["owner-a", "chat-with-newest-turn"],
    ).conversation_id);
    recordJournalExchange(store, {
      ownerId: "owner-a",
      conversationId,
      turns: [{
        turnId: "turn-newest",
        role: "user",
        surfaceKind: "main_chat",
        origin: "typed_chat",
        status: "completed",
        content: "Newest accepted turn",
        contentBlocks: [],
        createdAtMs: 1_000,
      }],
    });

    expect(kernel.listChatCatalog({ ownerId: "owner-a" }).map((chat) => chat.chatId)).toEqual([
      "chat-with-newest-turn",
      "chat-with-newer-session-row",
    ]);
    expect(kernel.listChatCatalog({ ownerId: "owner-a" })[1]?.lastActivityAtMs).toBe(1);
  });
});
