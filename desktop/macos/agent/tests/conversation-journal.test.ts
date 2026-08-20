import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  clearJournalConversation,
  getJournalObservability,
  listJournalTurns,
  migrateJournalConversation,
  recordJournalExchange,
  recordJournalTurn,
  updateJournalTurn,
} from "../src/runtime/conversation-journal.js";
import { SqliteAgentStore } from "../src/runtime/sqlite-store.js";
import { resolveSurfaceSession } from "../src/runtime/surface-session.js";

const createdDirs: string[] = [];

afterEach(() => {
  for (const directory of createdDirs.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function newDatabasePath(): string {
  const directory = mkdtempSync(join(tmpdir(), "omi-local-journal-"));
  createdDirs.push(directory);
  return join(directory, "agent.sqlite3");
}

function surface(
  store: SqliteAgentStore,
  ownerId: string,
  surfaceKind: string,
  chatId: string,
) {
  return resolveSurfaceSession(store, {
    ownerId,
    surfaceRef: { surfaceKind, externalRefKind: "chat", externalRefId: chatId },
    defaultAdapterId: "pi-mono",
  }, () => 1);
}

function completedTurn(
  store: SqliteAgentStore,
  input: { ownerId: string; conversationId: string; turnId: string; surfaceKind: string; content: string },
) {
  return recordJournalTurn(store, {
    ...input,
    role: "user",
    origin: input.surfaceKind === "realtime_voice" ? "realtime_voice" : "typed_chat",
    status: "completed",
    contentBlocks: [{ id: `${input.turnId}:text`, type: "text", text: input.content }],
    createdAtMs: 10,
  });
}

describe("kernel local conversation journal", () => {
  it("persists typed and voice turns in one canonical chat across restart", () => {
    const databasePath = newDatabasePath();
    let store = new SqliteAgentStore({ databasePath, reconcileOnOpen: false });
    const main = surface(store, "owner-a", "main_chat", "default");
    const voice = surface(store, "owner-a", "realtime_voice", "default");
    expect(voice.conversationId).toBe(main.conversationId);

    completedTurn(store, {
      ownerId: "owner-a",
      conversationId: main.conversationId,
      turnId: "typed-1",
      surfaceKind: "main_chat",
      content: "Typed locally",
    });
    completedTurn(store, {
      ownerId: "owner-a",
      conversationId: voice.conversationId,
      turnId: "voice-1",
      surfaceKind: "realtime_voice",
      content: "Spoken locally",
    });
    store.close();

    store = new SqliteAgentStore({ databasePath, reconcileOnOpen: false });
    const replay = listJournalTurns(store, {
      ownerId: "owner-a",
      conversationId: main.conversationId,
      limit: 20,
    });
    expect(replay.turns.map((turn) => [turn.turnId, turn.content])).toEqual([
      ["typed-1", "Typed locally"],
      ["voice-1", "Spoken locally"],
    ]);
    store.close();
  });

  it("keeps owner identity mandatory for every journal read and write", () => {
    const store = new SqliteAgentStore({ databasePath: newDatabasePath(), reconcileOnOpen: false });
    const owned = surface(store, "owner-a", "main_chat", "default");
    expect(() => completedTurn(store, {
      ownerId: "owner-b",
      conversationId: owned.conversationId,
      turnId: "forged",
      surfaceKind: "main_chat",
      content: "No",
    })).toThrow(/owner scope/);
    expect(() => listJournalTurns(store, {
      ownerId: "owner-b",
      conversationId: owned.conversationId,
    })).toThrow(/owner scope/);
    store.close();
  });

  it("records an exchange atomically and deduplicates stable turn identity", () => {
    const store = new SqliteAgentStore({ databasePath: newDatabasePath(), reconcileOnOpen: false });
    const owned = surface(store, "owner", "main_chat", "default");
    const input = {
      ownerId: "owner",
      conversationId: owned.conversationId,
      turns: [
        {
          turnId: "user-1",
          role: "user" as const,
          surfaceKind: "main_chat",
          origin: "typed_chat" as const,
          status: "completed" as const,
          content: "Question",
          contentBlocks: [{ id: "user-1:text", type: "text", text: "Question" }],
          metadataJson: JSON.stringify({ continuityKey: "exchange-1" }),
          createdAtMs: 10,
        },
        {
          turnId: "assistant-1",
          role: "assistant" as const,
          surfaceKind: "main_chat",
          origin: "agent_runtime" as const,
          status: "completed" as const,
          content: "Answer",
          contentBlocks: [{ id: "assistant-1:text", type: "text", text: "Answer" }],
          metadataJson: JSON.stringify({ continuityKey: "exchange-1" }),
          createdAtMs: 11,
        },
      ],
    };
    const firstReceipt = recordJournalExchange(store, input);
    expect(firstReceipt.createdTurns).toHaveLength(2);
    expect(firstReceipt.firstCompletedRealPair).toBe(true);
    expect(firstReceipt.firstCompletedRealExchange).toEqual({
      continuityKey: "exchange-1",
      userText: "Question",
      assistantText: "Answer",
    });
    const replayReceipt = recordJournalExchange(store, input);
    expect(replayReceipt.createdTurns).toHaveLength(0);
    expect(replayReceipt.firstCompletedRealPair).toBe(false);
    expect(() => recordJournalTurn(store, {
      ...input.turns[0],
      ownerId: "owner",
      conversationId: owned.conversationId,
      content: "Collision",
    })).toThrow(/different journal content/);
    store.close();
  });

  it("does not pair unrelated completed user and assistant turns", () => {
    const store = new SqliteAgentStore({ databasePath: newDatabasePath(), reconcileOnOpen: false });
    const owned = surface(store, "owner", "main_chat", "default");
    const receipt = recordJournalExchange(store, {
      ownerId: "owner",
      conversationId: owned.conversationId,
      turns: [
        {
          turnId: "user-unrelated",
          role: "user",
          surfaceKind: "main_chat",
          origin: "typed_chat",
          status: "completed",
          content: "Question",
          contentBlocks: [],
          metadataJson: JSON.stringify({ continuityKey: "user-exchange" }),
        },
        {
          turnId: "assistant-proactive",
          role: "assistant",
          surfaceKind: "main_chat",
          origin: "agent_runtime",
          status: "completed",
          content: "Unrelated notification",
          contentBlocks: [],
          metadataJson: JSON.stringify({ continuityKey: "proactive-exchange" }),
        },
      ],
    });

    expect(receipt.firstCompletedRealPair).toBe(false);
    expect(receipt.firstCompletedRealExchange).toBeNull();
    store.close();
  });

  it("updates local journal state and reports content-free health", () => {
    const store = new SqliteAgentStore({ databasePath: newDatabasePath(), reconcileOnOpen: false });
    const owned = surface(store, "owner", "main_chat", "default");
    recordJournalTurn(store, {
      ownerId: "owner",
      conversationId: owned.conversationId,
      turnId: "assistant-stream",
      role: "assistant",
      surfaceKind: "main_chat",
      origin: "agent_runtime",
      status: "streaming",
      content: "",
      contentBlocks: [],
    });
    updateJournalTurn(store, {
      ownerId: "owner",
      conversationId: owned.conversationId,
      turnId: "assistant-stream",
      status: "completed",
      content: "Done",
      appendContentBlocks: [{ id: "assistant-stream:text", type: "text", text: "Done" }],
    });
    expect(getJournalObservability(store, { ownerId: "owner" })).toEqual({
      turnStatusCounts: { completed: 1 },
    });
    store.close();
  });

  it("migrates the complete local turn graph without a shadow delivery store", () => {
    const store = new SqliteAgentStore({ databasePath: newDatabasePath(), reconcileOnOpen: false });
    const source = surface(store, "owner", "main_chat", "source");
    const destination = surface(store, "owner", "main_chat", "destination");
    completedTurn(store, {
      ownerId: "owner",
      conversationId: source.conversationId,
      turnId: "move-me",
      surfaceKind: "main_chat",
      content: "Portable",
    });
    const receipt = migrateJournalConversation(store, {
      ownerId: "owner",
      sourceConversationId: source.conversationId,
      destinationConversationId: destination.conversationId,
    });
    expect(receipt.movedTurnCount).toBe(1);
    expect(listJournalTurns(store, {
      ownerId: "owner",
      conversationId: destination.conversationId,
    }).turns.map((turn) => turn.turnId)).toEqual(["move-me"]);
    store.close();
  });

  it("clears only the local journal behind a generation fence", () => {
    const store = new SqliteAgentStore({ databasePath: newDatabasePath(), reconcileOnOpen: false });
    const owned = surface(store, "owner", "main_chat", "default");
    completedTurn(store, {
      ownerId: "owner",
      conversationId: owned.conversationId,
      turnId: "clear-me",
      surfaceKind: "main_chat",
      content: "Local",
    });
    const before = listJournalTurns(store, {
      ownerId: "owner",
      conversationId: owned.conversationId,
    });
    const cleared = clearJournalConversation(store, {
      ownerId: "owner",
      conversationId: owned.conversationId,
      expectedGeneration: before.generation,
    });
    expect(cleared).toMatchObject({ deletedTurns: 1, generation: before.generation + 1 });
    expect(listJournalTurns(store, {
      ownerId: "owner",
      conversationId: owned.conversationId,
    }).turns).toEqual([]);
    store.close();
  });
});
