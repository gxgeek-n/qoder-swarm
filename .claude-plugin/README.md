# .claude-plugin/

This directory is intentionally empty.

`qoder-swarm` targets **Qoder CLI** as its primary platform. The plugin
manifest lives at `../.qoder-plugin/plugin.json`.

If you want to use this kit with Claude Code:

1. Copy `../.qoder-plugin/plugin.json` to `./plugin.json` here.
2. Adjust paths if needed (Claude Code uses the same skill/agent/hook
   conventions as Qoder CLI, so most files work as-is).
3. Note that hooks and subagent runtime behavior may differ slightly
   between platforms — review `agents/swarm-*.md` and `hooks/swarm-*.sh`
   for any Qoder-specific commands before relying on them.

We don't ship a duplicate manifest by default because two identical
files drift over time and confuse `npm publish` consumers.
