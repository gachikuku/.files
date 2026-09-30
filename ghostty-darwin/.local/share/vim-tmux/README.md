# File links in tmux Vim

This macOS URL handler opens `cursor://file/...` links in Vim, in a new window
in the most recently active attached tmux session. Codex emits those links when
`file_opener = "cursor"` is set in `~/.codex/config.toml`. Directories open in
Finder.

It replaces TextEdit-owned file types and executable/script types with Vim.
Other default applications are preserved; in particular, JavaScript remains
associated with Chromium. Extensionless executables and scripts are edited
instead of run, so paths printed by commands such as `which` are safe to click.

Ghostty's own `open` child is routed through `~/bin/open`. That wrapper affects
only calls whose direct parent is Ghostty: TextEdit-owned files and scripts go
to Vim, while directories and everything else go unchanged to
`/usr/bin/open`. Normal shell use of `open` is not intercepted.
YouTube and direct audio/video links open with `mpv` in a new tmux window.
The wrapper stops a detected path at the first unescaped whitespace and
unescapes `\ ` inside real filenames, so adjacent prose is never passed to an
opener.

Use Command+Shift+click in Ghostty when tmux has mouse reporting enabled. File
citations with `:line` or `:line:column` suffixes open at that location.

Install this directory at `~/.local/share/vim-tmux` (the `ghostty-darwin` Stow
package provides it), then run:

```sh
sh ~/.local/share/vim-tmux/install.sh
```

Quit and relaunch Ghostty after installation so it inherits the configured GUI
`PATH`. The persistent PATH setting takes effect after the next login/reboot;
the installer also updates the live launchd environment for the next Ghostty
launch.

The handler does not create a tmux server or session. If several clients are
attached, it uses the session belonging to the most recently active client.

To remove it, unregister the app and delete it:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "$HOME/Applications/Vim in tmux.app"
```
