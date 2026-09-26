#!/bin/sh
set -eu

PATH="/run/current-system/sw/bin:$HOME/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app="$HOME/Applications/Vim in tmux.app"
mkdir -p "$HOME/Applications"
/usr/bin/osacompile -o "$app" "$source_dir/handler.applescript"
plist="$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string local.gachikuku.vim-tmux "$plist"
/usr/bin/plutil -replace CFBundleName -string 'Vim in tmux' "$plist"
/usr/bin/plutil -replace LSUIElement -bool YES "$plist"
/usr/bin/plutil -replace CFBundleURLTypes -json '[{"CFBundleURLName":"Vim in tmux","CFBundleURLSchemes":["cursor"],"CFBundleTypeRole":"Viewer"}]' "$plist"
/usr/bin/plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"Markdown document","CFBundleTypeRole":"Editor","LSHandlerRank":"Owner","CFBundleTypeExtensions":["md","markdown"],"LSItemContentTypes":["net.daringfireball.markdown"]},{"CFBundleTypeName":"Unix executable","CFBundleTypeRole":"Shell","LSHandlerRank":"Owner","LSItemContentTypes":["public.unix-executable"]}]' "$plist"
/usr/bin/codesign --force --sign - "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
duti -s local.gachikuku.vim-tmux cursor
duti -s local.gachikuku.vim-tmux md all
duti -s local.gachikuku.vim-tmux markdown all
duti -s local.gachikuku.vim-tmux public.unix-executable all
duti -s local.gachikuku.vim-tmux public.unix-executable shell
