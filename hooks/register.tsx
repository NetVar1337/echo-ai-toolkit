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

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    for (const name of Object.keys(AGENTS) as AgentName[]) {
      $.command.register({ name, description: AGENTS[name] });
    }
    $.command.register({ name: 'echo-help', description: 'List all Echo AI Toolkit agents' });
    $.command.register({ name: 'echo-reset', description: 'Clear active Echo agent context' });
    return next(e);
  });

  on('command.run', { command: 'echo-help' }, async ($, _e, _next) => {
    const lines = (Object.keys(AGENTS) as AgentName[])
      .map(k => `**/${k}** — ${AGENTS[k]}`)
      .join('\n');
    return {
      text: `## Echo AI Toolkit agents\n\n${lines}\n\nUse: \`Agent: echo-esp — write a CS2 bone ESP\`\nOr run a command (e.g. \`/echo-esp\`) to set context, then describe your task.`,
    };
  });

  on('command.run', { command: 'echo-reset' }, async ($, _e, _next) => {
    activeAgent = null;
    ($.state as Record<string, unknown>)['echo-ai-toolkit:agent'] = null;
    $.ui.status(undefined);
    return { text: 'Echo agent context cleared.' };
  });

  for (const name of Object.keys(AGENTS) as AgentName[]) {
    on('command.run', { command: name }, async ($, _e, _next) => {
      activeAgent = name;
      ($.state as Record<string, unknown>)['echo-ai-toolkit:agent'] = name;
      $.ui.status(`Echo: ${name}`);
      return {
        text: `**${name}** context active.\n\nNow describe your task — or open the agent directly:\n\`Agent: ${name} — <request>\``,
      };
    });
  }

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
