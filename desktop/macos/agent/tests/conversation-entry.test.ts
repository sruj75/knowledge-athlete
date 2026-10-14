import { afterEach, expect, test } from 'vitest';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const dirs: string[] = [];
afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });
test('storage entry boots without model credentials and rejects execution before touching history', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'conversation-entry-')); dirs.push(dir);
  const child = spawn(process.execPath, ['dist/index.js'], { env: { INTENTIVE_STORAGE_OWNER_ID: 'owner', HEYINTENTIVE_AGENT_STATE_DIR: dir }, stdio: ['pipe', 'pipe', 'pipe'] });
  const lines = createInterface({ input: child.stdout })[Symbol.asyncIterator]();
  const next = async () => JSON.parse((await lines.next()).value!) as Record<string, unknown>;
  try {
    expect(await next()).toMatchObject({ type: 'init', protocolVersion: 2, runtimeCapabilities: ['chat_catalog', 'conversation_journal'] });
    const common = { protocolVersion: 2, requestId: '1', clientId: 'test', ownerId: 'owner' };
    child.stdin.write(JSON.stringify({ ...common, type: 'query', prompt: 'execute' }) + '\n');
    expect(await next()).toMatchObject({ type: 'error', errorCode: 'invalid_conversation_request', requestId: '1' });
    child.stdin.write(JSON.stringify({ ...common, requestId: '2', type: 'journal_list_turns', surfaceKind: 'main_chat', externalRefKind: 'chat', externalRefId: 'default' }) + '\n');
    expect(await next()).toMatchObject({ type: 'journal_operation_result', conversationGeneration: 1, turns: [] });
  } finally { child.stdin.end(); child.kill(); }
});
