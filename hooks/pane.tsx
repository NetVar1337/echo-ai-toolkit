import type { Register } from 'claude-code';

// Quick-reference snippets shown in the side panel per active agent
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

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    $.ui.open({ id: 'echo-ai-toolkit:panel', title: 'Echo' });
    return next(e);
  });

  on('ui.render', { component: 'Pane', requestId: 'echo-ai-toolkit:panel' }, ($, e) => {
    const { Box, Text } = $.ui.resolve(e);
    const state = $.state as Record<string, unknown>;
    const agent = state['echo-ai-toolkit:agent'] as string | null | undefined;

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
