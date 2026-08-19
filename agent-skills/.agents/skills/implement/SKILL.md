---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Load and follow the installed `tdd` skill where possible, at pre-agreed seams. On a harness without a `Skill` tool, read its installed `SKILL.md` directly.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, load and follow the installed `code-review` skill. On a harness without a `Skill` tool, read its installed `SKILL.md` directly.

Before committing, verify that the diff contains no credentials, target artifacts, private-program material, raw traffic, decrypted binaries, or unredacted evidence. Commit the reviewed work to the current branch.
