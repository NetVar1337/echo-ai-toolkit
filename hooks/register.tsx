import { atom, read, update } from 'claude-code';
import type { Register } from 'claude-code';

const AGENT_INFO: Record<string, { desc: string; snippets: string[] }> = {
  'echo-esp': {
    desc: 'ESP visuals — boxes, bones, W2S per engine',
    snippets: [
      'source2.w2s(proc, vm_addr, pos, sx, sy)',
      'renderer.draw_rect_filled(x,y,w,h, col)',
      'renderer.draw_line(x1,y1,x2,y2, col, 1.5f)',
      'renderer.text(x, y, str, col, font)',
    ],
  },
  'echo-aimbot': {
    desc: 'Aim assist — FOV, smoothing, prediction, recoil',
    snippets: [
      'math.calc_fov(src, tgt, view_angles)',
      'math.lerp(cur_x, tgt_x, smooth)',
      'mouse.move(int(dx), int(dy))',
      'input.key_down(0x02)',
    ],
  },
  'echo-memory': {
    desc: 'Memory/RE — pattern scan, structs, Unicorn, Zydis',
    snippets: [
      'proc.scan_ida("48 8B 0D ? ? ? ?", "game.exe")',
      'proc.resolve_rip(addr, 3, 7)',
      'proc.read<uint64>(base + offset)',
      'proc.disasm_range(addr, 0x100)',
    ],
  },
  'echo-anticheat': {
    desc: 'AC awareness — detection surface, safe patterns',
    snippets: [
      'proc.query_regions()',
      'proc.get_module("EasyAntiCheat.sys")',
      'proc.get_module("vgk.sys")',
      'create_thread(64, function() { tick(); })',
    ],
  },
  'echo-sdk': {
    desc: 'Dumper-7 SDK — UE4/5 entity traversal, FName, VGK',
    snippets: [
      'proc.read<uint64>(gobjects)',
      'proc.read<uint64>(fname_pool + idx * 2)',
      'proc.read<float>(actor + health_off)',
      'proc.resolve_rip(gworld_instr, 3, 7)',
    ],
  },
  'echo-reverse': {
    desc: 'RE pipeline — static → Echo runtime; Zydis, OLLVM, REA',
    snippets: [
      'proc.disasm_range(addr, 0x200)',
      'emu.emu_start(fn_addr, fn_addr+0x500, 5000, 2000)',
      'proc.resolve_rip(lea_addr, 3, 7)',
      'proc.scan_ida("? ? ? ? ? ? E8", "game.exe")',
    ],
  },
  'echo-dev': {
    desc: 'General Echo API — threading, menu, networking',
    snippets: [
      'create_thread(64, function() { tick(); })',
      'menu_checkbox@ cb = menu.checkbox("Enable", false)',
      'menu.save_config("mymod")',
      'renderer.width() / renderer.height()',
    ],
  },
};

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

// catch AGENT_INFO/AGENTS drift at startup (adding an agent must update both)
export function validateAgentSync(
  agents: Record<string, unknown>,
  info: Record<string, unknown>
): void {
  const mismatched = Object.keys(agents).filter(k => !info[k]);
  if (mismatched.length) throw new Error(`echo-ai-toolkit: AGENT_INFO missing keys: ${mismatched.join(', ')}`);
}
validateAgentSync(AGENTS, AGENT_INFO);

// atom for active agent — written by commands/keyword detection, read by pane + prompt.compose
const agentAtom = atom({ plugin: 'echo-ai-toolkit', key: 'agent' } as const, null as AgentName | null);

// Derive install dir at module load; HOME must be a Unix path (starts with /)
const rawHome = (typeof process !== 'undefined')
  ? (process.env?.HOME ?? process.env?.USERPROFILE ?? '')
  : '';
const HOME: string = rawHome.startsWith('/') ? rawHome : '';
const ECHO_DEPS = `${HOME}/.local/share/echo-ai-toolkit`;
const GH_DIR    = `${ECHO_DEPS}/mcp-gamehacking`;
const ANGEL_DIR = `${ECHO_DEPS}/angel-menu-mcp`;

export const register: Register = (on) => {
  // ── session start ──────────────────────────────────────────────────────────
  on('session.start', async ($, e, next) => {
    for (const name of Object.keys(AGENTS) as AgentName[]) {
      await $.command.register({ name, description: AGENTS[name] });
    }
    await $.command.register({ name: 'echo-help',  description: 'List all Echo AI Toolkit agents' });
    await $.command.register({ name: 'echo-reset', description: 'Clear active Echo agent context' });
    await $.command.register({ name: 'echo-setup', description: 'Auto-install mcp-gamehacking, angel-menu-mcp, write .mcp.json' });
    void $.ui.open({ id: 'echo-ai-toolkit:panel', title: 'Echo' });

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
  on('command.run', { command: 'echo-help' }, async () => {
    const lines = (Object.keys(AGENTS) as AgentName[])
      .map(k => `**/${k}** — ${AGENTS[k]}`)
      .join('\n');
    return {
      text: `## Echo AI Toolkit agents\n\n${lines}\n\nUse: \`Agent: echo-esp — write a CS2 bone ESP\`\nOr run a slash command (e.g. \`/echo-esp\`) to set context, then describe your task.\n\nRun \`/echo-setup\` to auto-install all external dependencies.`,
    };
  });

  // ── /echo-reset ────────────────────────────────────────────────────────────
  on('command.run', { command: 'echo-reset' }, async ($) => {
    await update($, agentAtom, () => null);
    $.ui.status(undefined);
    return { text: 'Echo agent context cleared.' };
  });

  // ── /echo-setup ────────────────────────────────────────────────────────────
  on('command.run', { command: 'echo-setup' }, async ($) => {
    const log: string[] = [];
    const ok   = (msg: string) => { log.push(`✓ ${msg}`); };
    const err  = (msg: string, detail?: string) => {
      log.push(`✗ ${msg}${detail ? `: ${detail.slice(0, 100)}` : ''}`);
    };
    const skip = (msg: string) => { log.push(`↩ ${msg}`); };

    if (!HOME) {
      return { text: '## Echo Setup\n\n✗ $HOME is not set — cannot determine install directory.' };
    }

    // 1. Create deps dir
    await $.process.run(['mkdir', '-p', ECHO_DEPS]);

    // 2. Clone + build mcp-gamehacking
    {
      const built = await $.process.run(['test', '-f', `${GH_DIR}/dist/index.js`]);
      if (built.exitCode === 0) {
        skip('mcp-gamehacking already built');
      } else {
        let canBuild = true;
        const exists = await $.process.run(['test', '-d', GH_DIR]);
        if (exists.exitCode !== 0) {
          const clone = await $.process.run(
            ['git', 'clone', '--depth', '1', 'https://github.com/1llu50ry/mcp-gamehacking', GH_DIR],
            { timeoutMs: 180_000 }
          );
          if (clone.exitCode !== 0) {
            err('mcp-gamehacking clone', clone.stderr.trim());
            canBuild = false;
          }
        }
        if (canBuild) {
          // guard against dir existing but being empty/partial (no package.json)
          const hasPkg = await $.process.run(['test', '-f', `${GH_DIR}/package.json`]);
          if (hasPkg.exitCode !== 0) {
            err('mcp-gamehacking incomplete — delete the directory and run /echo-setup again');
            canBuild = false;
          }
        }
        if (canBuild) {
          const i = await $.process.run(['npm', 'install'], { cwd: GH_DIR, timeoutMs: 240_000 });
          const b = await $.process.run(['npm', 'run', 'build'], { cwd: GH_DIR, timeoutMs: 60_000 });
          (i.exitCode === 0 && b.exitCode === 0)
            ? ok('mcp-gamehacking built')
            : err('mcp-gamehacking build', b.stderr.trim());
        }
      }
    }

    // 3. Clone + install angel-menu-mcp
    {
      const ready = await $.process.run(['test', '-d', `${ANGEL_DIR}/node_modules`]);
      if (ready.exitCode === 0) {
        skip('angel-menu-mcp already installed');
      } else {
        let canInstall = true;
        const hasClone = await $.process.run(['test', '-f', `${ANGEL_DIR}/package.json`]);
        if (hasClone.exitCode !== 0) {
          const clone = await $.process.run(
            ['git', 'clone', '--depth', '1', 'https://github.com/Jozkah/angel-menu-mcp', ANGEL_DIR],
            { timeoutMs: 60_000 }
          );
          if (clone.exitCode !== 0) {
            err('angel-menu-mcp clone', clone.stderr.trim());
            canInstall = false;
          }
        }
        if (canInstall) {
          const i = await $.process.run(['npm', 'install'], { cwd: ANGEL_DIR, timeoutMs: 60_000 });
          i.exitCode === 0 ? ok('angel-menu-mcp installed') : err('angel-menu-mcp npm', i.stderr.trim());
        }
      }
    }

    // 4. Write .mcp.json with real paths
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

    await $.store.set('echo:setup-done', true);

    const manual = [
      '`/plugin install ponytail --marketplace DietrichGebert/ponytail`',
      '`/skills install multica-ai/andrej-karpathy-skills`',
      'IDA Pro MCP — requires IDA 9.4+ with idalib: `uvx ida-mcp`',
      'radare2 MCP — `r2pm -Uci r2mcp`',
      'REA auto-downloads on first MCP connect via `npx rea-agents` — no install needed',
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
    on('command.run', { command: name }, async ($) => {
      await update($, agentAtom, () => name);
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
          await update($, agentAtom, () => agent);
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
    const activeAgent = await read($, agentAtom);
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

  // ── side panel ────────────────────────────────────────────────────────────
  on('ui.render', { component: 'Pane', requestId: 'echo-ai-toolkit:panel' }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e);
    const agent = await read($, agentAtom);

    if (!agent) {
      return (
        <Box paddingX={1} paddingY={1} flexDirection="column" gap={1}>
          <Text bold color="yellow">Echo AI Toolkit</Text>
          <Text dimColor>No agent active.</Text>
          <Text dimColor>Use /echo-esp, /echo-reverse, etc.</Text>
          <Text dimColor>Or describe your task — keywords auto-route.</Text>
        </Box>
      );
    }

    const info = AGENT_INFO[agent];
    return (
      <Box paddingX={1} paddingY={1} flexDirection="column" gap={1}>
        <Box flexDirection="column">
          <Text bold color="yellow">{agent}</Text>
          <Text dimColor>{info?.desc ?? ''}</Text>
        </Box>
        <Box flexDirection="column">
          <Text dimColor>── quick ref ──────────────</Text>
          {(info?.snippets ?? []).map((s, i) => (
            <Text key={i} color="cyan">{s}</Text>
          ))}
        </Box>
        <Box flexDirection="column">
          <Text dimColor>── invoke ──────────────────</Text>
          <Text dimColor>{`Agent: ${agent} — <task>`}</Text>
        </Box>
      </Box>
    );
  });
};
