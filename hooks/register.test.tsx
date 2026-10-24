import { describe, it, expect, beforeEach } from 'claude-code/test';
import type { PluginTestHarness } from 'claude-code/test';
import { register, validateAgentSync } from './register';

describe('echo-ai-toolkit plugin', () => {
  let harness: PluginTestHarness;

  beforeEach(async () => {
    harness = await createTestHarness(register);
    await harness.emit('session.start', {});
  });

  // ── slash commands ──────────────────────────────────────────────────────────

  it('registers 9 slash commands on session start', () => {
    const cmds = harness.registeredCommands();
    expect(cmds).toContain('echo-help');
    expect(cmds).toContain('echo-reset');
    expect(cmds).toContain('echo-esp');
    expect(cmds).toContain('echo-reverse');
    expect(cmds.length).toBe(9); // 7 agents + echo-help + echo-reset
  });

  it('/echo-help returns a markdown table', async () => {
    const result = await harness.emit('command.run', { command: 'echo-help' });
    expect(result.text).toContain('echo-esp');
    expect(result.text).toContain('echo-reverse');
  });

  it('/echo-esp sets active agent and status', async () => {
    await harness.emit('command.run', { command: 'echo-esp' });
    expect(harness.status()).toContain('echo-esp');
  });

  it('/echo-reset clears active agent and status', async () => {
    await harness.emit('command.run', { command: 'echo-esp' });
    await harness.emit('command.run', { command: 'echo-reset' });
    expect(harness.status()).toBeUndefined();
    // prompt.compose should inject nothing after reset
    const composed = await harness.emit('prompt.compose', { text: 'write a bone ESP' });
    const hint = composed.sections?.find((s: { id: string }) => s.id === 'echo-ai-toolkit:agent-hint');
    expect(hint).toBeUndefined();
  });

  // ── keyword routing ─────────────────────────────────────────────────────────

  const keywordCases: [string, string][] = [
    ['write a W2S function',                         'echo-esp'],
    ['render bones on screen',                       'echo-esp'],
    ['aimbot with FOV filter',                       'echo-aimbot'],
    ['velocity prediction for bullet travel',        'echo-aimbot'],
    ['proc.scan_ida for entity list',                'echo-memory'],
    ['pointer chain to health',                      'echo-memory'],
    ['BattlEye detection surface',                   'echo-anticheat'],
    ['EAC kernel driver analysis',                   'echo-anticheat'],
    ['Dumper-7 GObjects traversal',                  'echo-sdk'],
    ['UE5 SDK generate offsets',                     'echo-sdk'],
    ['decompile this function in IDA',               'echo-reverse'],
    ['radare2 analysis of game.exe',                 'echo-reverse'],
    ['on_render callback in AngelScript',            'echo-dev'],
    ['menu.add checkbox to .as script',              'echo-dev'],
  ];

  for (const [text, expected] of keywordCases) {
    it(`"${text}" → ${expected}`, async () => {
      await harness.emit('prompt.submit', { text, command: null });
      expect(harness.status()).toContain(expected);
    });
  }

  it('keyword match does not fire when prompt is a command', async () => {
    await harness.emit('command.run', { command: 'echo-esp' });
    await harness.emit('prompt.submit', { text: 'IDA decompile', command: 'echo-esp' });
    expect(harness.status()).toContain('echo-esp');
  });

  // ── prompt.compose injection ─────────────────────────────────────────────

  it('injects agent-hint section when agent is active', async () => {
    await harness.emit('command.run', { command: 'echo-memory' });
    const result = await harness.emit('prompt.compose', { text: 'read entity health' });
    const hint = result.sections?.find((s: { id: string }) => s.id === 'echo-ai-toolkit:agent-hint');
    expect(hint).toBeDefined();
    expect(hint?.text).toContain('echo-memory');
  });

  it('does not inject hint when no agent is active', async () => {
    const result = await harness.emit('prompt.compose', { text: 'hello' });
    const hint = result.sections?.find((s: { id: string }) => s.id === 'echo-ai-toolkit:agent-hint');
    expect(hint).toBeUndefined();
  });

  it('handles undefined result.sections without throwing', async () => {
    harness.mockNextResult('prompt.compose', { sections: undefined });
    await harness.emit('command.run', { command: 'echo-esp' });
    await expect(
      harness.emit('prompt.compose', { text: 'test' })
    ).resolves.toBeDefined();
  });

  it('validateAgentSync throws when AGENTS has a key missing from AGENT_INFO', () => {
    expect(() => validateAgentSync({ 'echo-new': 'New agent' }, {})).toThrow('AGENT_INFO missing keys: echo-new');
  });
});
