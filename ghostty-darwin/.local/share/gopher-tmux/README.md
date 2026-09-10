# Gopher links in tmux

Ghostty opens links through macOS Launch Services. This app registers both
`gopher` and `gophers` and launches the selected browser in a new window in the
most recently active attached tmux session. URLs are passed as arguments without
shell interpretation. No tmux server or session is created.

Set `browser=sacc` or `browser=w3m` at the top of `open-gopher.sh` to choose
the browser. The default is `sacc`. Changes apply on the next click; no reinstall
or reload is needed. The tmux window is named after the selected browser.

Use Command+Shift+click in Ghostty when tmux has mouse reporting enabled.
This registration also applies to Gopher links opened from other macOS apps.
With multiple attached clients, the most recently active client determines the
session; macOS does not pass the originating terminal to a URL handler.
Default and named sockets under `/tmp/tmux-UID` are discovered automatically.

Install this directory at `~/.local/share/gopher-tmux` (the ghostty-darwin Stow
package provides it), then run `sh ~/.local/share/gopher-tmux/install.sh`.
Requires macOS's developer command line tools, `duti`, `tmux`, and the selected
browser (`sacc` or `w3m`).
The opener and installer are shell scripts; AppleScript receives macOS URL events.
Executable lookup prefers the Nix system profile and also checks `~/.local/bin`
(where this machine's `sacc` is installed) and `~/bin`.

The tmux configuration enables `xterm-ghostty:extkeys:hyperlinks` so senpai's
OSC 8 metadata reaches Ghostty and the entire URL, including `gophers://`, is
highlighted. Ghostty's automatic detection does not recognize that scheme.

To remove, unregister the app with `lsregister -u` and remove
`~/Applications/Gopher in tmux.app`.
