import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const home = process.env.USERPROFILE;
const cwd = process.cwd();
const timestamp = new Date(Date.now() - 60_000).toISOString();
const key = 'sk_FAKEwindowsCard0123456789abcdefABC';
const envFile = join(cwd, '.env');
const envContent = `STRIPE_SECRET_KEY=${key}\n`;

function writeJsonl(file, events) {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, `${events.map((event) => JSON.stringify(event)).join('\n')}\n`);
}

const claudeEvent = (role, content) => ({
  type: role,
  sessionId: 'windows-claude-fixture',
  cwd,
  timestamp,
  message: { role, content: [content] },
});
const projectSlug = cwd.replace(/[^a-zA-Z0-9]/g, '-');
writeJsonl(join(home, '.claude', 'projects', projectSlug, 'windows-claude-fixture.jsonl'), [
  claudeEvent('assistant', {
    type: 'tool_use',
    id: 'read-env',
    name: 'Read',
    input: { file_path: envFile },
  }),
  claudeEvent('user', { type: 'tool_result', tool_use_id: 'read-env', content: envContent }),
]);
writeFileSync(envFile, envContent);

const codexEvent = (type, payload) => ({ timestamp, type, payload });
const [year, month, day] = timestamp.slice(0, 10).split('-');
writeJsonl(join(home, '.codex', 'sessions', year, month, day, 'rollout-windows-fixture.jsonl'), [
  codexEvent('session_meta', { session_id: 'windows-codex-fixture', cwd, timestamp }),
  codexEvent('response_item', {
    type: 'function_call',
    name: 'shell',
    call_id: 'shell-1',
    arguments: JSON.stringify({ command: ['bash', '-lc', 'git status'] }),
  }),
  codexEvent('response_item', {
    type: 'function_call_output',
    call_id: 'shell-1',
    output: 'On branch main',
  }),
]);
