# Shared Agent Skills

Curated Matt Pocock skills for Pi and Codex.

## Installation

From the dotfiles root:

```sh
stow agent-skills
```

This exposes the skills under `~/.agents/skills/`, which Pi discovers natively and Matt Pocock documents as the shared Codex/Agent Skills location.

## Update policy

1. Clone/fetch upstream into a temporary audit directory.
2. Review the diff from the pinned commit in `UPSTREAM.md`.
3. Audit every selected skill, reference, script, and template.
4. Copy only the selected directories.
5. Reapply and review the local compatibility/security changes documented in `UPSTREAM.md`.
6. Run `bash -n` on bundled shell templates and start Pi once to inspect skill diagnostics.
7. Commit the reviewed update as one isolated dotfiles change.

Do not use an automatic updater. Skills are executable instructions and must not change behind the operator's back.
