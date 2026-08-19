#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NIX_DIR="$ROOT/nix"
DARWIN_REV="15abb8c98f336cd8bd840d71059adebabe60bf04"
STOW_PACKAGES=(agent-skills bin git nvim pi zsh)
NIX_FLAGS=(--extra-experimental-features "nix-command flakes")

bold=""; reset=""; green=""; yellow=""
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  bold=$(tput bold || true); reset=$(tput sgr0 || true)
  green=$(tput setaf 2 || true); yellow=$(tput setaf 3 || true)
fi

stage() { printf '\n%s==> %s%s\n' "$bold" "$1" "$reset"; }
pass() { printf '  %s✓%s %s\n' "$green" "$reset" "$1"; }
warn() { printf '  %s!%s %s\n' "$yellow" "$reset" "$1"; }
confirm() {
  local reply
  printf '  %s [y/N] ' "$1"
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

stage "Host identity"
[[ "$(uname -m)" == "arm64" ]] || { echo "Expected Apple silicon (arm64)." >&2; exit 1; }
[[ "$(id -un)" == "g4chi" ]] || {
  echo "Expected local account g4chi; current user is $(id -un)." >&2
  exit 1
}
pass "Apple silicon and local account match the flake"

stage "Apple command-line tools"
if xcode-select -p >/dev/null 2>&1; then
  pass "Xcode Command Line Tools are available"
else
  warn "Install Command Line Tools with: xcode-select --install"
  exit 1
fi

stage "Nix"
if command -v nix >/dev/null 2>&1; then
  pass "$(nix --version)"
else
  warn "Install Nix using your trusted installer, then rerun this script."
  exit 1
fi

stage "Evaluate and build the pinned h4c-mini system"
nix "${NIX_FLAGS[@]}" eval --raw "$NIX_DIR#darwinConfigurations.h4c-mini.config.system.build.toplevel.drvPath" >/dev/null
nix "${NIX_FLAGS[@]}" build --no-link "$NIX_DIR#darwinConfigurations.h4c-mini.config.system.build.toplevel"
pass "h4c-mini system closure builds"

stage "Activate nix-darwin"
if confirm "Run the privileged nix-darwin switch now?"; then
  sudo nix --extra-experimental-features "nix-command flakes" \
    run "github:LnL7/nix-darwin/${DARWIN_REV}#darwin-rebuild" -- \
    switch --flake "$NIX_DIR#h4c-mini"
  pass "h4c-mini profile activated"
  export PATH="/run/current-system/sw/bin:$PATH"
  hash -r
else
  warn "Skipped activation"
  exit 0
fi

stage "GNU Stow dotfiles"
cd "$ROOT"
stow_bin="$(command -v stow)"
for package in "${STOW_PACKAGES[@]}"; do
  "$stow_bin" --no --verbose "$package" >/dev/null
 done
if confirm "Stow ${STOW_PACKAGES[*]} into this account?"; then
  "$stow_bin" "${STOW_PACKAGES[@]}"
  "$ROOT/agent-skills/verify.sh"
  pass "dotfiles and audited skills linked"
else
  warn "Skipped Stow"
fi

stage "Tailscale"
tailscale_bin="$(command -v tailscale)"
if "$tailscale_bin" status >/dev/null 2>&1; then
  pass "Tailscale is already connected"
else
  warn "Tailscale needs interactive authorization. Running tailscale up."
  sudo "$tailscale_bin" up --hostname=h4c-mini
fi

stage "Local service checks"
/bin/launchctl print system/com.openssh.sshd >/dev/null
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
/usr/sbin/systemsetup -getcomputersleep
/usr/sbin/systemsetup -getrestartpowerfailure
pass "SSH launchd service and power/firewall settings are queryable"

cat <<'NEXT'

Remaining human work:
  1. Through NanoKVM, run: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
  2. From the current Mac, compare that fingerprint and run: ssh h4c-mini-breakglass
  3. Install Xcode and sign into the paid researcher Apple Account interactively.
  4. Insert/activate SIMs and complete the iPhone checklist.
  5. Configure the dedicated lab VLAN/SSID before target traffic begins.
NEXT
