# Syncing with ThePrimeagen's Config

His repo is cloned at `~/Developer/vimprime`

## When you get an RSS notification

1. Pull his latest changes:

```bash
cd ~/Developer/vimprime
git pull
```

2. Check what changed:

```bash
git log --oneline -10
git diff HEAD~1
```

3. Look at which files changed and manually apply the relevant parts to your config at `~/.files/nvim/.config/nvim/lua/gachikuku/`

## What to watch out for

- His files live under `lua/theprimeagen/` - yours are under `lua/gachikuku/`
- His colorscheme is `rose-pine-moon` - yours is `flexoki-light` - DO NOT copy his `colors.lua`
- His `local.lua` references `~/personal/harpoon` and `~/personal/99` - these are his local dev plugins, skip them
- Plugin GitHub URLs like `"ThePrimeagen/vim-be-good"` stay as-is (that's the real repo name)
- Everything else with `theprimeagen` or `ThePrimeagen` in variable/augroup names should be renamed to `gachikuku` or `Gachikuku`

## Files mapping

| His file | Your file |
|----------|-----------|
| `lua/theprimeagen/init.lua` | `lua/gachikuku/init.lua` |
| `lua/theprimeagen/set.lua` | `lua/gachikuku/set.lua` |
| `lua/theprimeagen/remap.lua` | `lua/gachikuku/remap.lua` |
| `lua/theprimeagen/lazy_init.lua` | `lua/gachikuku/lazy_init.lua` |
| `lua/theprimeagen/lazy/*.lua` | `lua/gachikuku/lazy/*.lua` |

## Your custom stuff (don't overwrite these parts)

- `colors.lua` - your flexoki-light theme
- `vimwiki.lua` - your iCloud wiki setup
- `set.lua` - your personal vim options
- In `remap.lua` the section at the bottom marked `-- gachikuku custom`:
  - `<leader>pp` paste mode
  - `<leader>ue` / `<leader>ud` URL encode/decode
  - `<leader>l` list toggle
- In `init.lua`:
  - MitmproxySettings autocmd
  - PersistentFormatOptions autocmd
  - No trailing whitespace removal on save (prime has it, you don't want it)

## Quick diff command

To see what's different between his config and yours:

```bash
diff -r ~/Developer/vimprime/lua/theprimeagen/ ~/.files/nvim/.config/nvim/lua/gachikuku/ --exclude="*.json"
```

## Skip these files from his repo

- `local.lua` - references `~/personal/harpoon` which is a local path on his machine (99 is split into its own file)
- `jai.lua` - Jai language support, only useful if you write Jai
- `golf.lua` - code golf plugin for his streams
- `tj.lua` - TJ DeVries' PHP plugin
- `peek.lua` - disabled (commented out)
- `supermaven.lua` - disabled (commented out)
- `markdown.lua` - empty, returns nothing
- `unused_copilot.lua` - disabled (commented out)
