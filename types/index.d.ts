export type AgentName =
  | 'echo-dev'
  | 'echo-esp'
  | 'echo-aimbot'
  | 'echo-memory'
  | 'echo-anticheat'
  | 'echo-sdk'
  | 'echo-reverse';

declare module 'claude-code' {
  interface PluginState {
    'echo-ai-toolkit': { agent: AgentName | null }
  }
}
