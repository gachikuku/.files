#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd)"
expected=(
  code-review codebase-design diagnosing-bugs domain-modeling grill-with-docs
  grilling handoff implement prototype research setup-matt-pocock-skills tdd
  to-spec to-tickets wayfinder wizard writing-for-agents
)

bash -n "$repo/.agents/skills/wizard/template.sh"
bash -n "$repo/.agents/skills/diagnosing-bugs/scripts/hitl-loop.template.sh"

for name in "${expected[@]}"; do
  pi_path="$HOME/.agents/skills/$name/SKILL.md"
  codex_path="$HOME/.codex/skills/$name/SKILL.md"
  [[ -r "$pi_path" ]] || { echo "missing Pi skill: $name" >&2; exit 1; }
  [[ -r "$codex_path" ]] || { echo "missing Codex skill: $name" >&2; exit 1; }
  [[ "$(realpath "$pi_path")" == "$(realpath "$codex_path")" ]] || {
    echo "Pi/Codex copies diverged: $name" >&2
    exit 1
  }
done

if find -L "$HOME/.agents/skills" "$HOME/.codex/skills" -type l -print -quit | grep -q .; then
  echo "broken skill symlink found" >&2
  exit 1
fi

node_root="$HOME/.pi/agent"
[[ -d "$node_root/node_modules/@earendil-works/pi-coding-agent" ]] || node_root="$HOME/.files/pi/.pi/agent"
cd "$node_root"
PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.files/pi/.pi/agent}" \
EXPECTED_SKILLS="${expected[*]}" \
node --input-type=module <<'JS'
import { DefaultResourceLoader, getAgentDir } from '@earendil-works/pi-coding-agent';
const loader = new DefaultResourceLoader({ cwd: process.env.HOME, agentDir: getAgentDir() });
await loader.reload();
const { skills, diagnostics } = loader.getSkills();
const found = new Set(skills.map((skill) => skill.name));
const missing = process.env.EXPECTED_SKILLS.split(' ').filter((name) => !found.has(name));
if (missing.length) {
  console.error(`Pi loader missing: ${missing.join(', ')}`);
  process.exit(1);
}
const selectedDiagnostics = diagnostics.filter((d) => process.env.EXPECTED_SKILLS.includes(d.name ?? ''));
if (selectedDiagnostics.length) {
  console.error(JSON.stringify(selectedDiagnostics, null, 2));
  process.exit(1);
}
JS

printf 'OK: %s audited skills resolve to one canonical copy for Pi and Codex.\n' "${#expected[@]}"
