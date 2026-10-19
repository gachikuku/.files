# Autonomous macOS execution

- For authorized privileged shell work, prefer `/usr/bin/sudo -n --` when available. If sudo requires a password, retrieve `default_password` from gopass and supply it through stdin without printing, logging, or embedding it in command arguments.
- Prefer noninteractive command-line interfaces for macOS administration, Xcode setup, installers, services, and system configuration.
- In generated AppleScript, route privileged setup through the same CLI authentication path with safely quoted arguments.
- When controlling a GUI app, perform its privileged setup with an equivalent CLI command first. Do not trigger Authorization Services, Keychain-password, or Apple Account credential dialogs; when macOS provides no noninteractive interface, report that exact boundary rather than opening a credential prompt.
- Open Privacy/TCC consent prompts when needed for an authorized task. Approve a permission when the user has explicitly authorized that specific access; otherwise leave approval to the user.
