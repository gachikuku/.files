#!/bin/sh
set -eu
PATH="/run/current-system/sw/bin:$HOME/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app="$HOME/Applications/Gopher in tmux.app"
mkdir -p "$HOME/Applications"
/usr/bin/osacompile -o "$app" "$source_dir/handler.applescript"
plist="$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string local.gachikuku.gopher-tmux "$plist"
/usr/bin/plutil -replace CFBundleName -string 'Gopher in tmux' "$plist"
/usr/bin/plutil -replace LSUIElement -bool YES "$plist"
/usr/bin/plutil -replace CFBundleURLTypes -json '[{"CFBundleURLName":"Gopher in tmux","CFBundleURLSchemes":["gopher","gophers"],"CFBundleTypeRole":"Viewer"}]' "$plist"
/usr/bin/codesign --force --sign - "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
duti -s local.gachikuku.gopher-tmux gopher
duti -s local.gachikuku.gopher-tmux gophers
