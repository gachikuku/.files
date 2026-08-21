# Hack Mini Bootstrap

The `h4c-mini` nix-darwin configuration is for the Apple-silicon Mac mini. It enables Tailscale, key-only OpenSSH, firewall stealth mode, no system/display sleep or automatic GUI logout, restart after power failure/freeze, pinned research CLI tools, and the existing GNU Stow workflow.

## Human prerequisites

1. Complete macOS Setup Assistant with the existing local account `g4chi`.
2. Install macOS updates only during this commissioning window.
3. Install Xcode Command Line Tools (`xcode-select --install`).
4. Install Nix using the same trusted installer/channel used on the existing Mac.
5. Clone the public dotfiles repository:

   ```sh
   git clone https://github.com/gachikuku/.files.git ~/.files
   ```

6. Run the guided bootstrap:

   ```sh
   ~/.files/nix/bootstrap-h4c-mini.sh
   ```

The script pauses before the privileged nix-darwin switch and before Stow changes.

## Privileged autonomy

The owner explicitly selected unrestricted passwordless sudo for the dedicated `g4chi` administrator so unattended maintenance can execute arbitrary root commands. This means every process and agent running as `g4chi` can fully control the host. SSH remains key-only and network reachability must stay restricted.

## What the profile deliberately does not contain

- Private SSH keys, Apple passwords, 2FA codes, app-specific passwords, signing private keys, Tailscale auth keys, gopass private keys, phone identifiers, or target credentials.
- Xcode itself. Install Xcode through Apple's supported distribution while signed into the dedicated paid researcher account.
- Automatic macOS major updates.
- Automatic HackerOne submission or target authorization.

## SSH

The flake installs the current Mac's ED25519 **public** key for `g4chi`. Password and keyboard-interactive SSH are disabled, root login and agent forwarding are disabled, and forwarding is limited to local forwards.

After the mini joins the tailnet with hostname `h4c-mini`, the current Mac has two aliases:

```sh
ssh h4c-mini             # attach/create tmux session research
ssh h4c-mini-breakglass  # plain shell if tmux/config is broken
```

On first connection, compare the mini host-key fingerprint with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` displayed through NanoKVM before accepting it.

## Stow

The bootstrap offers these packages:

```sh
cd ~/.files
stow agent-skills astral-tmux bin git nvim pi zsh
```

The shared Matt Pocock skills then resolve from one canonical copy for Pi and Codex. Add other Stow packages only when the mini actually needs them.

## Apple/Xcode handoff

Sign into the paid researcher Apple Account interactively in Xcode, enable automatic signing, and let Xcode create a development identity on this Mac. Routine WebDriverAgent builds use the signing identity and Xcode account state in Keychain; agents do not receive the Apple Account password or 2FA recovery material.

App-specific passwords are for supported third-party access to iCloud Mail, Contacts, and Calendar. They are not a substitute for Xcode, App Store, or Apple Developer portal authentication.

## Persistent iOS automation services

The host profile declares two launchd jobs:

- `org.nixos.h4c-appium`: GUI LaunchAgent, listening only on `127.0.0.1:4723`.
- `org.nixos.h4c-remotexpc`: root LaunchDaemon, with its registry only on `127.0.0.1:42314` and automatic tunnel recreation for connected devices.

Appium must run in the logged-in Aqua session because WDA builds need the user's unlocked signing Keychain. After a Mac reboot, Appium therefore remains unavailable until a human logs into the GUI. Phone automation also waits for each phone's human-only first unlock; the Dopamine phone additionally needs a human re-jailbreak before jailbreak-dependent work.

Check service and tunnel health:

```sh
curl -fsS http://127.0.0.1:4723/status | jq .value.ready
curl -fsS http://127.0.0.1:42314/remotexpc/tunnels | jq .metadata
launchctl print gui/$(id -u)/org.nixos.h4c-appium
sudo launchctl print system/org.nixos.h4c-remotexpc
sudo lsof -nP -iTCP:4723 -iTCP:42314 -sTCP:LISTEN
```

Logs are intentionally local:

```text
~/Library/Logs/h4c-appium.stdout.log
~/Library/Logs/h4c-appium.stderr.log
/var/root/Library/Logs/h4c-remotexpc.stdout.log
/var/root/Library/Logs/h4c-remotexpc.stderr.log
```

Do not expose either service through router forwarding or bind them to all interfaces. The pinned Appium package patches the RemoteXPC registry and ephemeral USB relay listeners to loopback. It also allows the unprivileged Appium process to consume the fixed registry port because the root daemon and GUI agent use separate state directories.

RemoteXPC tunnel discovery can take about a minute after boot. Wait for `.metadata.activeTunnels` to reach the expected device count before opening Appium sessions. Personal Team WDA startup may take several minutes.

## Deploying a prebuilt system closure

Running a system closure's `activate` script alone changes the live system but does **not** make that closure the next boot generation. When this workstation builds and copies a closure to the mini, set the system profile before activation:

```sh
system=$(nix build .#darwinConfigurations.h4c-mini.system --no-link --print-out-paths)
nix copy --to ssh://h4c-mini-breakglass "$system"
ssh h4c-mini-breakglass \
  "sudo nix-env -p /nix/var/nix/profiles/system --set '$system' && sudo '$system/activate'"
```

Verify both links resolve to the intended closure before rebooting:

```sh
readlink -f /nix/var/nix/profiles/system
readlink /run/current-system
```
