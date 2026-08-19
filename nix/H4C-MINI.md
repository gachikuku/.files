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
stow agent-skills bin git nvim pi zsh
```

The shared Matt Pocock skills then resolve from one canonical copy for Pi and Codex. Add other Stow packages only when the mini actually needs them.

## Apple/Xcode handoff

Sign into the paid researcher Apple Account interactively in Xcode, enable automatic signing, and let Xcode create a development identity on this Mac. Routine WebDriverAgent builds use the signing identity and Xcode account state in Keychain; agents do not receive the Apple Account password or 2FA recovery material.

App-specific passwords are for supported third-party access to iCloud Mail, Contacts, and Calendar. They are not a substitute for Xcode, App Store, or Apple Developer portal authentication.
