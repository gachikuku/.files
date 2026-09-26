# File links in tmux Vim

This macOS URL handler opens `cursor://file/...` links in Vim, in a new window
in the most recently active attached tmux session. Codex emits those links when
`file_opener = "cursor"` is set in `~/.codex/config.toml`.

It is also registered as the default opener for `.md` and `.markdown` files,
because Ghostty can hand a detected Markdown path to macOS as an ordinary
document instead of preserving the editor URL. Other document types keep their
existing default applications, except extensionless Unix executables. Those are
opened for editing instead of being run, so paths printed by commands such as
`which` are safe to click. The installer assigns both the general and Shell
Launch Services roles because macOS dispatches Unix executables through the
Shell role.

Use Command+Shift+click in Ghostty when tmux has mouse reporting enabled. File
citations with `:line` or `:line:column` suffixes open at that location.

Install this directory at `~/.local/share/vim-tmux` (the `ghostty-darwin` Stow
package provides it), then run:

```sh
sh ~/.local/share/vim-tmux/install.sh
```

The handler does not create a tmux server or session. If several clients are
attached, it uses the session belonging to the most recently active client.

To remove it, unregister the app and delete it:

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "$HOME/Applications/Vim in tmux.app"
```
