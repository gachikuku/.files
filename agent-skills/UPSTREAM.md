# Upstream Provenance

- Repository: https://github.com/mattpocock/skills
- Pinned commit: `885e2ca4d842d139e9aef4e48d366c63cb1b8013`
- Commit date: 2026-08-19T14:09:18+01:00
- License: MIT; see `LICENSE.mattpocock-skills`
- Audit date: 2026-08-19

## Selected skills

- setup-matt-pocock-skills
- grill-with-docs
- grilling
- domain-modeling
- wayfinder
- research
- prototype
- handoff
- writing-for-agents
- wizard
- to-spec
- to-tickets
- implement
- tdd
- diagnosing-bugs
- codebase-design
- code-review

## Local changes

- Cross-skill instructions support Pi's direct `SKILL.md` loading when a generic `Skill` tool is unavailable.
- Canonical skills are stowed to `~/.agents/skills`; relative links expose the same files under `~/.codex/skills` because Codex 0.147 did not discover the shared global location.
- Pi command references use `/skill:<name>`.
- `implement` adds a pre-commit check for credentials and private research artifacts.
- `wizard` follows the local gopass policy: secrets are not persisted to plaintext `.env` by default.
- `wizard/template.sh` adds `write_gopass`, treats `write_env` as non-secret-only, and no longer reloads secrets from `.env`.

These changes are intentional and must be re-reviewed/reapplied when updating upstream.
