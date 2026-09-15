# Phone notifications

Only the root agent may send a breakthrough notification. Subagents must never
send phone notifications.

When a commentary update reports a verified positive breakthrough, also run:

```sh
/run/current-system/sw/bin/python3 ~/.codex/hooks/pushover_notify.py breakthrough "<short summary>"
```

A verified positive breakthrough means one of these happened:

- A root cause was confirmed with evidence.
- A major blocker was removed.
- An important previously failing validation now passes.
- A risky or uncertain approach was conclusively validated.

Do not notify for routine progress, investigation, searches, reads, edits,
waiting, plans, optimistic expectations, or individual subagent activity. Send
at most two breakthrough notifications per goal. The command also enforces a
30-minute cooldown per project.

Do not manually notify for goal completion, goal blockage, permission requests,
questions, or root-turn stops. Codex lifecycle hooks handle those events.
