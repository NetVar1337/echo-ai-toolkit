import type { Register } from 'claude-code';

const AGENTS = {
  'echo-dev':       'General Echo API — threading, menu, networking, utilities',
  'echo-esp':       'ESP visuals — boxes, bones, health bars, W2S per engine',
  'echo-aimbot':    'Aimbot — FOV filter, smoothing, prediction, recoil, triggerbot',
  'echo-memory':    'Memory/RE — pointer chains, structs, pattern scan, Unicorn, Zydis',
  'echo-anticheat': 'AC awareness — detection surface, safe coding patterns, risk matrix',
  'echo-sdk':       'Dumper-7 SDK — UE4/5 entity traversal, FName, VGK decrypt',
  'echo-reverse':   'RE pipeline — static → Echo runtime; Zydis xref, OLLVM, REA',
} as const;

type AgentName = keyof typeof AGENTS;

const KEYWORDS: [RegExp, AgentName][] = [
  [/\b(esp|bones?|skeleton|w2s|world[\s_]?to[\s_]?screen|cornered[\s_]?box)\b/i, 'echo-esp'],
  [/\b(aimbot|aim[\s_]?assist|fov|smooth(ing)?|triggerbot|velocity[\s_]?pred)\b/i, 'echo-aimbot'],
  [/\b(pattern[\s_]?scan|scan_ida|unicorn|zydis|disasm|emulat|pointer[\s_]?chain)\b/i, 'echo-memory'],
  [/\b(anti[-_]?cheat|vac\b|eac\b|battleye|vanguard|byfron|ricochet)\b/i, 'echo-anticheat'],
  [/\b(dumper[-_]?7|gobjects|fname\b|ue[45]\b|unreal[\s_]?sdk)\b/i, 'echo-sdk'],
  [/\b(decompil|ida\b|radare2?|ghidra|ollvm|reverse[\s_]?eng|rea\b)\b/i, 'echo-reverse'],
  [/\b(angelscript|\.as\b|echo[\s_]?api|menu\.add|on_render|create_thread|proc\.read)\b/i, 'echo-dev'],
];

let activeAgent: AgentName | null = null;

// Derive install dir at module load; no shell needed — Node process.env is available at runtime
const HOME: string = (typeof process !== 'undefined' && process.env?.HOME) ? process.env.HOME
  : (typeof process !== 'undefined' && process.env?.USERPROFILE) ? (process.env.USERPROFILE as string)
  : '';
const ECHO_DEPS = `${HOME}/.local/share/echo-ai-toolkit`;
const GH_DIR    = `${ECHO_DEPS}/mcp-gamehacking`;
const ANGEL_DIR = `${ECHO_DEPS}/angel-menu-mcp`;

export const register: Register = (on) => {
  // ── session start: register all commands + first-run notice ───────────────
  on('session.start', async ($, e, next) => {
    for (const name of Object.keys(AGENTS) as AgentName[]) {
      $.command.register({ name, description: AGENTS[name] });
    }
    $.command.register({ name: 'echo-help',  description: 'List all Echo AI Toolkit agents' });
    $.command.register({ name: 'echo-reset', description: 'Clear active Echo agent context' });
    $.command.register({ name: 'echo-setup', description: 'Auto-install all dependencies: mcp-gamehacking, REA, angel-menu-mcp, update .mcp.json' });

    const done = await $.store.get('echo:setup-done');
    if (!done) {
      const notified = await $.store.get('echo:setup-notified');
      if (!notified) {
        await $.store.set('echo:setup-notified', true);
        $.ui.notice('Echo AI Toolkit: run /echo-setup to auto-install mcp-gamehacking, REA, and angel-menu-mcp.');
      }
    }

    return next(e);
  });

  // ── /echo-help ─────────────────────────────────────────────────────────────
  on('command.run', { command: 'echo-help' }, async (_$, _e, _next) => {
    const lines = (Object.keys(AGENTS) as AgentName[])
      .map(k => `**/${k}** — ${AGENTS[k]}`)
      .join('\n');
    return {
      text: `## Echo AI Toolkit agents\n\n${lines}\n\nUse: \`Agent: echo-esp — write a CS2 bone ESP\`\nOr run a slash command (e.g. \`/echo-esp\`) to set context, then describe your task.\n\nRun \`/echo-setup\` to auto-install all external dependencies.`,
    };
  });

  // ── /echo-reset ────────────────────────────────────────────────────────────
  on('command.run', { command: 'echo-reset' }, async ($, _e, _next) => {
    activeAgent = null;
    ($.state as Record<string, unknown>)['echo-ai-toolkit:agent'] = null;
    $.ui.status(undefined);
    return { text: 'Echo agent context cleared.' };
  });

  // ── /echo-setup — auto-installs everything possible ────────────────────────
  on('command.run', { command: 'echo-setup' }, async ($, _e, _next) => {
    const log: string[] = [];
    const ok  = (msg: string) => { log.push(`✓ ${msg}`); };
    const err = (msg: string, detail?: string) => {
      log.push(`✗ ${msg}${detail ? `: ${detail.slice(0, 100)}` : ''}`);
    };
    const skip = (msg: string) => { log.push(`↩ ${msg}`); };

    // 1. Create deps dir
    await $.process.run(['mkdir', '-p', ECHO_DEPS]);

    // 2. Install rea-agents (npm global)
    {
      const r = await $.process.run(['npm', 'install', '-g', 'rea-agents'], { timeoutMs: 120_000 });
      r.exitCode === 0 ? ok('rea-agents installed') : err('rea-agents', r.stderr.trim());
    }

    // 3. Clone + build mcp-gamehacking
    {
      const built = await $.process.run(['test', '-f', `${GH_DIR}/dist/index.js`]);
      if (built.exitCode === 0) {
        skip('mcp-gamehacking already built');
      } else {
        const exists = await $.process.run(['test', '-d', GH_DIR]);
        if (exists.exitCode !== 0) {
          const clone = await $.process.run(
            ['git', 'clone', '--depth', '1', 'https://github.com/1llu50ry/mcp-gamehacking', GH_DIR],
            { timeoutMs: 180_000 }
          );
          if (clone.exitCode !== 0) { err('mcp-gamehacking clone', clone.stderr.trim()); }
        }
        const i = await $.process.run(['npm', 'install'], { cwd: GH_DIR, timeoutMs: 240_000 });
        const b = await $.process.run(['npm', 'run', 'build'], { cwd: GH_DIR, timeoutMs: 60_000 });
        (i.exitCode === 0 && b.exitCode === 0)
          ? ok('mcp-gamehacking built')
          : err('mcp-gamehacking build', b.stderr.trim());
      }
    }

    // 4. Clone + install angel-menu-mcp
    {
      const exists = await $.process.run(['test', '-f', `${ANGEL_DIR}/index.js`]);
      if (exists.exitCode === 0) {
        skip('angel-menu-mcp already installed');
      } else {
        const clone = await $.process.run(
          ['git', 'clone', '--depth', '1', 'https://github.com/Jozkah/angel-menu-mcp', ANGEL_DIR],
          { timeoutMs: 60_000 }
        );
        if (clone.exitCode !== 0) {
          err('angel-menu-mcp clone', clone.stderr.trim());
        } else {
          const i = await $.process.run(['npm', 'install'], { cwd: ANGEL_DIR, timeoutMs: 60_000 });
          i.exitCode === 0 ? ok('angel-menu-mcp installed') : err('angel-menu-mcp npm', i.stderr.trim());
        }
      }
    }

    // 5. Write .mcp.json with real paths into the working directory
    {
      const config = {
        mcpServers: {
          gamehacking: {
            command: 'node',
            args: [`${GH_DIR}/dist/index.js`],
            description: 'mcp-gamehacking: 4100+ skills, 75 agents, 16 tools',
          },
          rea: {
            command: 'npx',
            args: ['rea-agents'],
            description: 'REA: static binary analysis — Unity IL2CPP, Godot, APK, WASM',
          },
          radare2: {
            command: 'r2pm',
            args: ['-r', 'r2mcp'],
            description: 'radare2 MCP (install: r2pm -Uci r2mcp)',
          },
          ida: {
            command: 'uvx',
            args: ['ida-mcp', 'stdio', '--agent=my-agent'],
            description: 'IDA Pro MCP (requires IDA 9.4+)',
          },
          'angel-menu': {
            command: 'node',
            args: [`${ANGEL_DIR}/index.js`],
            description: 'Echo overlay menu control',
          },
        },
      };
      const json = JSON.stringify(config, null, 2);
      const w = await $.process.run(['tee', '.mcp.json'], { stdin: json });
      w.exitCode === 0 ? ok('.mcp.json written with real paths') : err('.mcp.json write', w.stderr.trim());
    }

    // 6. Mark setup done
    await $.store.set('echo:setup-done', true);

    // 7. Remaining manual steps
    const manual = [
      '`/plugin install ponytail --marketplace DietrichGebert/ponytail`',
      '`/skills install multica-ai/andrej-karpathy-skills`',
      'IDA Pro MCP — requires IDA 9.4+ with idalib: `uvx ida-mcp`',
      'radare2 MCP — `r2pm -Uci r2mcp`',
    ];

    return {
      text: [
        '## Echo Setup',
        '',
        log.join('\n'),
        '',
        '**Still needs manual install:**',
        manual.map(s => `- ${s}`).join('\n'),
        '',
        'Run `/reload-plugins` to activate new MCP servers.',
      ].join('\n'),
    };
  });

  // ── agent context slash commands ───────────────────────────────────────────
  for (const name of Object.keys(AGENTS) as AgentName[]) {
    on('command.run', { command: name }, async ($, _e, _next) => {
      activeAgent = name;
      ($.state as Record<string, unknown>)['echo-ai-toolkit:agent'] = name;
      $.ui.status(`Echo: ${name}`);
      return {
        text: `**${name}** context active.\n\nDescribe your task — or open the agent directly:\n\`Agent: ${name} — <request>\``,
      };
    });
  }

  // ── keyword auto-route ─────────────────────────────────────────────────────
  on('prompt.submit', async ($, e, next) => {
    if (!e.command) {
      for (const [pattern, agent] of KEYWORDS) {
        if (pattern.test(e.text)) {
          activeAgent = agent;
          ($.state as Record<string, unknown>)['echo-ai-toolkit:agent'] = agent;
          $.ui.status(`Echo: ${agent}`);
          break;
        }
      }
    }
    return next(e);
  });

  // ── system-prompt injection ────────────────────────────────────────────────
  on('prompt.compose', async ($, e, next) => {
    const result = await next(e);
    if (!activeAgent) return result;
    return {
      ...result,
      sections: [
        ...(result.sections ?? []),
        {
          id: 'echo-ai-toolkit:agent-hint',
          scope: 'session' as const,
          text: `[Echo AI Toolkit] Active context: **${activeAgent}**. Full API reference and patterns are in \`.claude/agents/${activeAgent}.md\`. Suggest: \`Agent: ${activeAgent} — <task>\` (project install) or \`Agent: echo-ai-toolkit:${activeAgent} — <task>\` (plugin install).`,
        },
      ],
    };
  });
};
