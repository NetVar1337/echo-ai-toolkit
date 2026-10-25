import type { Register } from 'claude-code';

const AGENT_INFO: Record<string, { desc: string; snippets: string[] }> = {
  'echo-dev': {
    desc: 'General Echo API — threading, menu, networking, utilities',
    snippets: [
      'create_thread(64, @tick);   // 1-128 tps, 0 = run once',
      'on_render(@render_tick);   // render-thread callback',
      'checkbox c = ui::add_checkbox("Enable", false);',
      'bool v = ui::get(c); ui::set(c, v);',
    ],
  },
  'echo-esp': {
    desc: 'ESP visuals — boxes, bones, W2S per engine',
    snippets: [
      'vec2 screen; source2::w2s(world_pos, view_matrix, screen);',
      'render::draw_box(x, y, w, h, 255, 0, 0, 255, box_style::FILLED, 0.0f);',
      'render::draw_line(x1, y1, x2, y2, 255, 255, 255, 255, 1.0f);',
      'render::draw_text(x, y, "name", 255, 255, 255, 255);',
    ],
  },
  'echo-aimbot': {
    desc: 'Aim assist — FOV, smoothing, prediction, recoil',
    snippets: [
      'double fov = math::calculate_fov(view_angles, target_angles);',
      'vec2 smooth = math::smooth_angles(cur, tgt, angle_range::R_180, 0.3, 1.0, 45.0);',
      'input::mouse_move(x, y);   // absolute screen coords',
      'input::key_active(0x02);',
    ],
  },
  'echo-memory': {
    desc: 'Memory/RE — pointer chains, structs, pattern scan, Unicorn, Zydis',
    snippets: [
      'uint64 base = process::get_module_base("game.exe");',
      'uint64 sig = process::find_signature(base, "48 8B 0D ? ? ? ?");',
      'uint64 target = process::get_relative_address(sig, 3, 7);',
      'zydis::disasm(bytes, addr, insns);',
    ],
  },
  'echo-anticheat': {
    desc: 'AC awareness — detection surface, safe coding patterns',
    snippets: [
      'process::virtual_query(addr);   // one region',
      'process::get_module_base("EasyAntiCheat.sys");',
      'process::is_alive();',
      'create_thread(64, @tick);',
    ],
  },
  'echo-sdk': {
    desc: 'Dumper-7 SDK — UE4/5 entity traversal, FName, VGK',
    snippets: [
      'process::read_uint64(gobjects);',
      'process::read_float(actor + health_off);',
      'process::get_relative_address(gworld_instr, 3, 7);',
      'u_bone_array b = unreal::read_bones(mesh, off, cached_off, comp);',
    ],
  },
  'echo-reverse': {
    desc: 'RE pipeline — static → Echo runtime; Zydis, OLLVM, REA',
    snippets: [
      'array<uint8>@ b = process::read_bytes(addr, 0x100);',
      'zydis::disasm_func(b, addr, insns);',
      'process::get_relative_address(lea_addr, 3, 7);',
      'uc::start(h, fn_addr, fn_addr + 0x500, 5000, 2000);',
    ],
  },
  'echo-config': {
    desc: 'Config & data layer — persistence, HTTP, fs, ws, json',
    snippets: [
      'ui::config_path("my_script");',
      'file::write("cfg.json", data);',
      'json::parse(text);',
      'http::get(url, @on_response);',
    ],
  },
  'echo-radar': {
    desc: '2D radar/minimap overlay — world→radar transform, entity dots',
    snippets: [
      'vec2 screen; source2::w2s(world_pos, view_matrix, screen);',
      'render::draw_circle(cx + dx, cy + dy, 4, 255, 0, 0, 255, true, 16);',
      'render::draw_polyline(points, 255, 255, 255, 255, 1.0f, true);',
      'render::get_viewport_size();',
    ],
  },
  'echo-loot': {
    desc: 'Item/loot ESP — entity class filtering, tiers, dropped weapons',
    snippets: [
      'string cls = process::read_string(entity + 0x10);',
      'render::draw_text(x, y, item_name, 255, 200, 0, 255);',
      'render::calculate_text_size(item_name);',
      'render::draw_box(x, y, w, h, 255, 255, 0, 255, box_style::OUTLINED, 0.0f);',
    ],
  },
  'echo-triggerbot': {
    desc: 'Triggerbot — crosshair detection, shot delay, burst, per-hitbox',
    snippets: [
      'input::key_active(0x02);   // VK_LBUTTON held',
      'input::key_press(0x02);',
      'input::key_release(0x02);',
      'input::mouse_click();',
    ],
  },
  'echo-scripts': {
    desc: 'Complete runnable example scripts — CS2 ESP, UE4 aimbot, Unity loot',
    snippets: [
      'bool main() { return true; }',
      'void on_unload() { /* teardown */ }',
      'create_thread(64, @tick);',
      'on_render(@render_tick);',
    ],
  },
};

const AGENTS = {
  'echo-dev':       'General Echo API — threading, menu, networking, utilities',
  'echo-esp':       'ESP visuals — boxes, bones, health bars, W2S per engine',
  'echo-aimbot':    'Aimbot — FOV filter, smoothing, prediction, recoil',
  'echo-memory':    'Memory/RE — pointer chains, structs, pattern scan, Unicorn, Zydis',
  'echo-anticheat': 'AC awareness — detection surface, safe patterns, risk matrix',
  'echo-sdk':       'Dumper-7 SDK — UE4/5 entity traversal, FName, VGK decrypt',
  'echo-reverse':   'RE pipeline — static → Echo runtime; Zydis xref, OLLVM, REA',
  'echo-config':    'Config & data layer — persistence, HTTP, fs, ws, json',
  'echo-radar':     '2D radar/minimap overlay — world→radar transform, entity dots',
  'echo-loot':      'Item/loot ESP — entity class filtering, item tiers, loot panels',
  'echo-triggerbot':'Triggerbot — crosshair detection, shot delay, burst, per-hitbox',
  'echo-scripts':   'Complete runnable example scripts — CS2 ESP, UE4 aimbot, Unity loot',
} as const;

type AgentName = keyof typeof AGENTS;

/** Every agent this plugin exposes — keep in sync with agents/*.md */
export const AGENT_NAMES = Object.keys(AGENTS) as AgentName[];

// Ordered most-specific first: broad terms (esp, script) must not shadow narrower ones
// ("loot ESP" is a loot task, not a generic ESP task).
const KEYWORDS: [RegExp, AgentName][] = [
  [/\b(triggerbot|auto[\s_]?fire|crosshair|shot[\s_]?delay)\b/i, 'echo-triggerbot'],
  [/\b(radar|minimap|compass)\b/i, 'echo-radar'],
  [/\b(loot|dropped?[\s_]?item|item[\s_]?tier|pickup)\b/i, 'echo-loot'],
  [/\b(dumper[-_]?7|gobjects|fname\b|ue[45]\b|unreal[\s_]?sdk)\b/i, 'echo-sdk'],
  [/\b(pattern[\s_]?scan|scan_ida|find_signature|unicorn|zydis|disasm|emulat|pointer[\s_]?chain)\b/i, 'echo-memory'],
  [/\b(decompil|ida\b|radare2?|ghidra|ollvm|reverse[\s_]?eng|rea\b)\b/i, 'echo-reverse'],
  [/\b(anti[-_]?cheat|vac\b|eac\b|battleye|vanguard|byfron|ricochet)\b/i, 'echo-anticheat'],
  [/\b(config|persist|http|websocket|\bws\b|json|hashmap|hashset|save[\s_]?config)\b/i, 'echo-config'],
  [/\b(aimbot|aim[\s_]?assist|\bfov\b|smooth(ing)?|velocity[\s_]?pred\w*|bullet[\s_]?pred\w*)\b/i, 'echo-aimbot'],
  [/\b(esp|bones?|skeleton|w2s|world[\s_]?to[\s_]?screen|cornered[\s_]?box)\b/i, 'echo-esp'],
  [/\b(template|example[\s_]?script|sample[\s_]?script|runnable)\b/i, 'echo-scripts'],
  [/\b(angelscript|\.as\b|echo[\s_]?api|ui::add|on_render|create_thread|process::read)\b/i, 'echo-dev'],
];

// catch AGENT_INFO/AGENTS drift at startup (adding an agent must update both)
export function validateAgentSync(
  agents: Record<string, unknown>,
  info: Record<string, unknown>
): void {
  const mismatched = Object.keys(agents).filter(k => !info[k]);
  if (mismatched.length) throw new Error(`echo-ai-toolkit: AGENT_INFO missing keys: ${mismatched.join(', ')}`);
  const orphanInfo = Object.keys(info).filter(k => !agents[k]);
  if (orphanInfo.length) throw new Error(`echo-ai-toolkit: AGENTS missing keys: ${orphanInfo.join(', ')}`);
}
validateAgentSync(AGENTS, AGENT_INFO);

// Active agent — written by the slash commands and by keyword detection, read by
// the pane and by prompt.compose. Module scope lasts for the whole session, which
// is exactly the lifetime this value needs.
let activeAgent: AgentName | null = null;

// Derive install dir at module load; HOME must be a Unix path (starts with /)
const rawHome = (typeof process !== 'undefined')
  ? (process.env?.HOME ?? process.env?.USERPROFILE ?? '')
  : '';
const HOME: string = rawHome.startsWith('/') ? rawHome : '';

export const register: Register = (on) => {
  // ── session start ──────────────────────────────────────────────────────────
  on('session.start', async ($, e, next) => {
    for (const name of Object.keys(AGENTS) as AgentName[]) {
      await $.command.register({ name, description: AGENTS[name] });
    }
    await $.command.register({ name: 'echo-help',  description: 'List all Echo AI Toolkit agents' });
    await $.command.register({ name: 'echo-reset', description: 'Clear active Echo agent context' });
    await $.command.register({ name: 'echo-setup', description: 'Install the plugin and every companion tool (runs install.sh / install.ps1)' });
    await $.command.register({ name: 'echo-tier',  description: 'Show or set the install tier: minimal | standard | full' });
    // The side panel is a nicety: a failure to open it must never break the session.
    await $.ui.open({ id: 'echo-ai-toolkit-panel', title: 'Echo' }).catch(() => {});

    const done = await $.store.get('echo:setup-done');
    if (!done) {
      const notified = await $.store.get('echo:setup-notified');
      if (!notified) {
        await $.store.set('echo:setup-notified', true);
        $.ui.notice('Echo AI Toolkit: run /echo-setup to install the MCP servers and all 17 companion tools.');
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
    activeAgent = null;
    $.ui.status(undefined);
    return { text: 'Echo agent context cleared.' };
  });

  // ── /echo-setup ────────────────────────────────────────────────────────────
  // The installer script is the single source of truth for what gets installed
  // (plugin + 17 companion tools, tiered). This command just runs it.
  on('command.run', { command: 'echo-setup' }, async ($) => {
    if (!HOME) {
      return { text: '## Echo Setup\n\n✗ $HOME is not set — cannot determine install directory.' };
    }

    const pluginRoot = (process.env?.CLAUDE_PLUGIN_ROOT ?? '').trim();
    if (!pluginRoot) {
      return {
        text: [
          '## Echo Setup',
          '',
          '✗ `CLAUDE_PLUGIN_ROOT` is not set, so the bundled installer cannot be located.',
          '',
          'Run it directly instead:',
          '```',
          'curl -fsSL https://raw.githubusercontent.com/NetVar1337/echo-ai-toolkit/main/install.sh | bash',
          '```',
        ].join('\n'),
      };
    }

    const isWindows = process.platform === 'win32';
    const script = `${pluginRoot}/${isWindows ? 'install.ps1' : 'install.sh'}`;
    const tier = (await $.store.get('echo:tier')) ?? 'standard';
    const cmd = isWindows
      ? ['pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script]
      : ['bash', script];

    const r = await $.process.run(cmd, {
      env: { ECHO_TIER: String(tier) },
      timeoutMs: 900_000,
    });

    const out = [r.stdout.trim(), r.stderr.trim()].filter(Boolean).join('\n');
    if (r.exitCode === 0) await $.store.set('echo:setup-done', true);

    return {
      text: [
        '## Echo Setup',
        '',
        `Ran \`${isWindows ? 'install.ps1' : 'install.sh'}\` (tier: **${tier}**).`,
        '',
        '```',
        out.slice(-4000) || '(no output)',
        '```',
        '',
        r.exitCode === 0
          ? 'Run `/reload-plugins` to activate the MCP servers.'
          : 'Some tools failed — see the summary above, or run `./scripts/echo-doctor.sh` for detail.',
        '',
        'Tier is `echo:tier` in the plugin store. Set it with `/echo-tier full|standard|minimal`.',
      ].join('\n'),
    };
  });

  // ── /echo-tier ─────────────────────────────────────────────────────────────
  on('command.run', { command: 'echo-tier' }, async ($, e) => {
    const want = String((e as { args?: string })?.args ?? '').trim();
    const valid = ['minimal', 'standard', 'full'];
    if (!valid.includes(want)) {
      const cur = (await $.store.get('echo:tier')) ?? 'standard';
      return {
        text: [
          `## Echo install tier`,
          '',
          `Current: **${cur}**`,
          '',
          '| Tier | Installs | Needs |',
          '|---|---|---|',
          '| `minimal` | plugin + MCP servers | Node 18+ |',
          '| `standard` | + Echo tooling, Python tooling, docs | Node + Python |',
          '| `full` | + CMake/.NET devirt stack, LLVM, web-mv | + compilers |',
          '',
          'Set with `/echo-tier minimal|standard|full`, then run `/echo-setup`.',
        ].join('\n'),
      };
    }
    await $.store.set('echo:tier', want);
    return { text: `Tier set to **${want}**. Run \`/echo-setup\` to apply it.` };
  });

  // ── agent context slash commands ───────────────────────────────────────────
  for (const name of Object.keys(AGENTS) as AgentName[]) {
    on('command.run', { command: name }, async ($) => {
      activeAgent = name;
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
          text: `[Echo AI Toolkit] Active context: **${activeAgent}**. Full API reference and patterns are in \`agents/${activeAgent}.md\` (plugin install) or \`.claude/agents/${activeAgent}.md\` (project install). Suggest: \`Agent: ${activeAgent} — <task>\` (project install) or \`Agent: echo-ai-toolkit:${activeAgent} — <task>\` (plugin install).`,
        },
      ],
    };
  });

  // ── side panel ────────────────────────────────────────────────────────────
  on('ui.render', { component: 'Pane', requestId: 'echo-ai-toolkit-panel' }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e);
    const agent = activeAgent;

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
