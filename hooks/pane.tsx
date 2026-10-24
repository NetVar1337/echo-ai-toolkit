import type { Register } from 'claude-code';

// Quick-reference snippets shown in the side panel per active agent
const AGENT_INFO: Record<string, { desc: string; snippets: string[] }> = {
  'echo-esp': {
    desc: 'ESP visuals — boxes, bones, W2S per engine',
    snippets: [
      'math.world_to_screen(vp, pos, screen)',
      'draw.rect(x, y, w, h, col, 1.5f)',
      'draw.line(a, b, col, 1.0f)',
      'draw.text(x, y, str, col, 12.f)',
    ],
  },
  'echo-aimbot': {
    desc: 'Aim assist — FOV, smoothing, prediction, recoil',
    snippets: [
      'math.angle_to_target(local_pos, enemy_pos)',
      'math.calc_velocity_pred(pos, vel, bullet_spd)',
      'mouse.move(delta_x, delta_y)',
      'math.fov_check(cam_angles, target_angles, fov)',
    ],
  },
  'echo-memory': {
    desc: 'Memory/RE — pattern scan, structs, Unicorn, Zydis',
    snippets: [
      'proc.scan_ida("48 8B 0D ? ? ? ?", "game.exe")',
      'proc.resolve_rip(addr, 3, 7)',
      'proc.read<uint64>(base + offset)',
      'disasm.decode_function(proc, addr)',
    ],
  },
  'echo-anticheat': {
    desc: 'AC awareness — detection surface, safe patterns',
    snippets: [
      'proc.query_regions()',
      'proc.get_module("EasyAntiCheat.sys")',
      'proc.get_module("vgk.sys")',
      'create_thread(tps, @tick)',
    ],
  },
  'echo-sdk': {
    desc: 'Dumper-7 SDK — UE4/5 entity traversal, FName, VGK',
    snippets: [
      'proc.read<uint64>(gobjects)',
      'proc.read_wstring(fname_pool + idx * 2, 64)',
      'proc.read<matrix4x4>(actor + 0x1B0)',
      'proc.read<float>(uobject + health_offset)',
    ],
  },
  'echo-reverse': {
    desc: 'RE pipeline — static → Echo runtime; Zydis, OLLVM, REA',
    snippets: [
      'disasm.decode_function(proc, addr)',
      'emu.start(fn_addr, fn_addr + 0x500, 5000, 2000)',
      'proc.resolve_rip(lea_addr, 3, 7)',
      'proc.scan_ida("? ? ? ? ? ? E8", "game.exe")',
    ],
  },
  'echo-dev': {
    desc: 'General Echo API — threading, menu, networking',
    snippets: [
      'on_render(@cb)',
      'create_thread(0, @fn)',
      'menu.add_checkbox("label", @val)',
      'config.write_bool("key", val)',
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
