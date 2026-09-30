#!/bin/sh
set -eu

PATH="/run/current-system/sw/bin:$HOME/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PATH

source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app="$HOME/Applications/Vim in tmux.app"
open_wrapper="$HOME/.files/bin/bin/open"
mkdir -p "$HOME/Applications"
/usr/bin/osacompile -o "$app" "$source_dir/handler.applescript"
plist="$app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string local.gachikuku.vim-tmux "$plist"
/usr/bin/plutil -replace CFBundleName -string 'Vim in tmux' "$plist"
/usr/bin/plutil -replace LSUIElement -bool YES "$plist"
/usr/bin/plutil -replace CFBundleURLTypes -json '[{"CFBundleURLName":"Vim in tmux","CFBundleURLSchemes":["cursor"],"CFBundleTypeRole":"Viewer"}]' "$plist"
/usr/bin/plutil -replace CFBundleDocumentTypes -json '[{"CFBundleTypeName":"TextEdit-owned file","CFBundleTypeRole":"Editor","LSHandlerRank":"Owner","CFBundleTypeExtensions":["*"],"LSItemContentTypes":["public.data"]},{"CFBundleTypeName":"Markdown document","CFBundleTypeRole":"Editor","LSHandlerRank":"Owner","CFBundleTypeExtensions":["md","markdown"],"LSItemContentTypes":["net.daringfireball.markdown"]},{"CFBundleTypeName":"JSON document","CFBundleTypeRole":"Editor","LSHandlerRank":"Owner","CFBundleTypeExtensions":["json"],"LSItemContentTypes":["public.json"]},{"CFBundleTypeName":"Zig source","CFBundleTypeRole":"Editor","LSHandlerRank":"Owner","CFBundleTypeExtensions":["zig"]},{"CFBundleTypeName":"Unix executable","CFBundleTypeRole":"Shell","LSHandlerRank":"Owner","LSItemContentTypes":["public.unix-executable"]},{"CFBundleTypeName":"Script","CFBundleTypeRole":"Shell","LSHandlerRank":"Owner","CFBundleTypeExtensions":["sh","bash","zsh","fish","py","rb","pl","php","lua"],"LSItemContentTypes":["public.script","public.shell-script","public.bash-script","public.zsh-script","public.python-script","public.ruby-script","public.perl-script","public.php-script"]}]' "$plist"
/usr/bin/codesign --force --sign - "$app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f "$app"
duti -s local.gachikuku.vim-tmux cursor
duti -s local.gachikuku.vim-tmux md all
duti -s local.gachikuku.vim-tmux markdown all
duti -s local.gachikuku.vim-tmux public.json all
duti -s local.gachikuku.vim-tmux .json all
duti -s local.gachikuku.vim-tmux public.unix-executable all
duti -s local.gachikuku.vim-tmux public.unix-executable shell

# Replace TextEdit only. Existing browser/media/preview defaults are preserved.
"$lsregister" -dump | awk '$1 == "uti:" {print $2}' | sort -u |
while IFS= read -r uti; do
    [ "$uti" != public.data ] || continue
    handler=$(duti -d "$uti" 2>/dev/null || true)
    [ "$handler" = com.apple.TextEdit ] || continue
    duti -s local.gachikuku.vim-tmux "$uti" all || true
done

for uti in \
    public.shell-script \
    public.bash-script \
    public.zsh-script \
    public.python-script \
    public.ruby-script \
    public.perl-script \
    public.php-script
do
    duti -s local.gachikuku.vim-tmux "$uti" all
    duti -s local.gachikuku.vim-tmux "$uti" shell
done

# Ghostty resolves its macOS opener by PATH. Keep ordinary shell calls to
# `open` unchanged; the wrapper activates only when Ghostty is its parent.
[ -x "$open_wrapper" ] || {
    printf 'Ghostty open wrapper is missing or not executable: %s\n' "$open_wrapper" >&2
    exit 1
}
mkdir -p "$HOME/bin"
if [ ! -e "$HOME/bin/open" ] && [ ! -L "$HOME/bin/open" ]; then
    ln -s ../.files/bin/bin/open "$HOME/bin/open"
fi
[ "$(readlink "$HOME/bin/open" 2>/dev/null || true)" = ../.files/bin/bin/open ] || {
    printf 'Refusing to replace existing %s\n' "$HOME/bin/open" >&2
    exit 1
}
gui_path="$HOME/bin:/usr/bin:/bin:/usr/sbin:/sbin"
launchctl setenv PATH "$gui_path"
/usr/bin/sudo -n -- launchctl config user path "$gui_path"
