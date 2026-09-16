# Autonomous macOS execution

- Route authorized privileged shell work through `/usr/bin/sudo -n --`; this Mac already grants the user passwordless sudo. Treat a nonzero result as an execution failure instead of requesting credentials.
- Prefer noninteractive command-line interfaces for macOS administration, Xcode setup, installers, services, and system configuration.
- In generated AppleScript, perform privileged commands through `/usr/bin/sudo -n --` with safely quoted arguments. Never use `do shell script ... with administrator privileges`, because that invokes the macOS password sheet instead of the configured noninteractive sudo path.
- When controlling a GUI app, perform its privileged setup with an equivalent CLI command first. Do not trigger Authorization Services, Keychain-password, Apple Account, or Privacy/TCC dialogs; when macOS provides no noninteractive interface, report that exact boundary rather than opening a credential prompt.
