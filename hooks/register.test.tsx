import { test, expect } from 'claude-code/testing';
import { register, validateAgentSync, AGENT_NAMES } from './register';

/** Collects what the plugin sends to the engine, so assertions can inspect it. */
type Recorder = {
  commands: string[];
  statuses: string[];
};

/**
 * Stand in for the engine: nothing sits beneath the plugin, so every hook the
 * plugin calls has to be answered here. Each event may only be hooked once, so
 * the recorder is the single sink for everything the plugin emits.
 */
function stubEngine(on: (event: string, handler: (...args: never[]) => unknown) => void): Recorder {
  const recorder: Recorder = { commands: [], statuses: [] };

  on('command.register', (_: unknown, e: unknown) => {
    const name = readString(e, 'name');
    if (name) recorder.commands.push(name);
    return { value: {} };
  });
  on('session.start', (_: unknown, e: unknown) => ({ cwd: readString(e, 'cwd') }));
  // Plugin state is namespaced per plugin: { 'echo-ai-toolkit': { agent } }.
  on('state.get', () => ({ value: { agent: null } }));
  on('state.set', () => ({ value: { agent: null } }));
  on('store.get', () => ({ value: null }));
  on('store.set', () => ({ value: null }));
  on('ui.status', (_: unknown, e: unknown) => {
    const value = readString(e, 'text');
    if (value) recorder.statuses.push(value);
    return { value: undefined };
  });
  on('ui.notice', () => ({ value: undefined }));
  // ui.resolve answers with the element table itself.
  on('ui.resolve', () => ({}));
  on('ui.render', () => ({ value: {} }));
  on('ui.open', () => ({ value: {} }));
  on('process.run', () => ({ value: { exitCode: 0, stdout: '', stderr: '' } }));
  // prompt.submit answers the submitted text; the plugin's routing hook must
  // forward it unchanged.
  on('prompt.submit', () => ({ text: 'echoed' }));
  // prompt.compose answers the composed prompt; the plugin appends a section.
  on('prompt.compose', () => ({ sections: [] }));

  return recorder;
}

/** Read a string field off an untyped hook payload. */
function readString(payload: unknown, key: string): string | undefined {
  const value = readUnknown(payload, key);
  return typeof value === 'string' ? value : undefined;
}

/** Read a field off an untyped hook payload. */
function readUnknown(payload: unknown, key: string): unknown {
  if (payload && typeof payload === 'object' && key in payload) {
    return (payload as Record<string, unknown>)[key];
  }
  return undefined;
}

const SESSION = { cwd: '/', surface: 'desktop', isInteractive: true } as const;

/** The full fact-set the engine hands to prompt.compose / prompt.submit. */
const PROMPT_FACTS = {
  text: '',
  args: '',
  command: null,
  outputStyle: null,
  promptModel: 'claude-opus-4',
  tools: [],
  traits: [],
  surfaces: [],
} as const;

test('session.start registers every agent as a slash command', async ($, on) => {
  const rec = stubEngine(on);
  await $.session.start(SESSION);

  for (const agent of AGENT_NAMES) {
    expect(rec.commands).toContain(agent);
  }
  expect(rec.commands).toContain('echo-help');
  expect(rec.commands).toContain('echo-reset');
  expect(rec.commands).toContain('echo-setup');
  // 12 agents + 3 utilities
  expect(rec.commands.length).toBe(AGENT_NAMES.length + 3);
});

test('/echo-help lists every agent', async ($, on) => {
  stubEngine(on);
  await $.session.start(SESSION);

  const result = await $.command.run({ command: 'echo-help' });
  for (const agent of AGENT_NAMES) {
    expect(result.text).toContain(agent);
  }
});

test('/echo-<agent> sets the active agent', async ($, on) => {
  const rec = stubEngine(on);
  await $.session.start(SESSION);

  await $.command.run({ command: 'echo-esp' });
  expect(rec.statuses.join(' ')).toContain('echo-esp');
});

test('/echo-reset clears the active agent', async ($, on) => {
  stubEngine(on);
  await $.session.start(SESSION);

  await $.command.run({ command: 'echo-esp' });
  await $.command.run({ command: 'echo-reset' });

  const composed = await $.prompt.compose({ ...PROMPT_FACTS });
  const hint = composed.sections?.find((s: { id: string }) => s.id === 'echo-ai-toolkit:agent-hint');
  expect(hint).toBeUndefined();
});

test('prompt.compose injects the active agent hint', async ($, on) => {
  stubEngine(on);
  await $.session.start(SESSION);

  await $.command.run({ command: 'echo-memory' });
  const composed = await $.prompt.compose({ ...PROMPT_FACTS });
  const hint = composed.sections?.find((s: { id: string }) => s.id === 'echo-ai-toolkit:agent-hint');
  expect(hint).toBeDefined();
  expect(hint?.text).toContain('echo-memory');
});

test('prompt.compose does not inject a hint when no agent is active', async ($, on) => {
  stubEngine(on);
  await $.session.start(SESSION);

  const composed = await $.prompt.compose({ ...PROMPT_FACTS });
  const hint = composed.sections?.find((s: { id: string }) => s.id === 'echo-ai-toolkit:agent-hint');
  expect(hint).toBeUndefined();
});

const keywordCases: [string, string][] = [
  ['write a W2S function',                  'echo-esp'],
  ['render bones on screen',                'echo-esp'],
  ['aimbot with FOV filter',                'echo-aimbot'],
  ['velocity prediction for bullet travel', 'echo-aimbot'],
  ['find_signature pattern scan',           'echo-memory'],
  ['pointer chain to health',               'echo-memory'],
  ['BattlEye detection surface',            'echo-anticheat'],
  ['EAC kernel driver analysis',            'echo-anticheat'],
  ['Dumper-7 GObjects traversal',           'echo-sdk'],
  ['UE5 SDK generate offsets',              'echo-sdk'],
  ['decompile this function in IDA',        'echo-reverse'],
  ['radare2 analysis of game.exe',          'echo-reverse'],
  ['on_render callback in AngelScript',     'echo-dev'],
  ['ui::add checkbox to .as script',        'echo-dev'],
  ['triggerbot with shot delay',            'echo-triggerbot'],
  ['radar minimap overlay',                 'echo-radar'],
  ['loot ESP for dropped items',            'echo-loot'],
  ['persist config over http',              'echo-config'],
  ['give me a runnable example script',     'echo-scripts'],
];

for (const [text, expected] of keywordCases) {
  test(`keyword routing: "${text}" → ${expected}`, async ($, on) => {
    const rec = stubEngine(on);
    await $.session.start(SESSION);

    await $.prompt.submit({ ...PROMPT_FACTS, text, args: text });
    expect(rec.statuses.join(' ')).toContain(expected);
  });
}

test('keyword routing does not fire when the prompt is a command', async ($, on) => {
  const rec = stubEngine(on);
  await $.session.start(SESSION);

  await $.prompt.submit({ ...PROMPT_FACTS, text: 'IDA decompile', args: 'IDA decompile', command: 'echo-esp' });
  expect(rec.statuses.join(' ')).not.toContain('echo-reverse');
});

test('validateAgentSync throws when AGENTS has a key missing from AGENT_INFO', () => {
  expect(() => validateAgentSync({ 'echo-new': 'New agent' }, {})).toThrow('AGENT_INFO missing keys: echo-new');
});

test('validateAgentSync throws when AGENT_INFO has an orphan key', () => {
  expect(() => validateAgentSync({}, { 'echo-new': 'New agent' })).toThrow('AGENTS missing keys: echo-new');
});
