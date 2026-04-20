claude --resume 038b49fb-66cb-4c23-be9b-509674a69d84

# Neovim Keybindings Cheatsheet

Leader key: `<Space>`

## Navigation & Movement

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>pv` | Normal | Open netrw file explorer |
| `<C-d>` | Normal | Page down, cursor stays centered |
| `<C-u>` | Normal | Page up, cursor stays centered |
| `n` | Normal | Next search result, centered |
| `N` | Normal | Previous search result, centered |
| `J` | Normal | Join lines but cursor stays in place |
| `=ap` | Normal | Auto-indent current paragraph |

## Editing & Clipboard

| Key | Mode | What it does |
|-----|------|-------------|
| `J` / `K` | Visual | Move selected lines down / up |
| `<leader>p` | Visual | Paste over selection without losing your clipboard |
| `<leader>y` | Normal/Visual | Yank to system clipboard |
| `<leader>Y` | Normal | Yank entire line to system clipboard |
| `<leader>d` | Normal/Visual | Delete to void register (doesn't overwrite clipboard) |
| `<C-c>` | Insert | Escape (same as `<Esc>`) |
| `<leader>pp` | Normal | Paste from system clipboard (paste mode) |

## Search & Replace

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>s` | Normal | Find and replace word under cursor across the file |
| `<leader>l` | Normal | Toggle whitespace visibility (tabs, spaces, EOL) |

## File Operations

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>x` | Normal | Make current file executable (`chmod +x`) |
| `<leader><leader>` | Normal | Source (reload) current file |

## Telescope (Fuzzy Finder)

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>pf` | Normal | Find files in project |
| `<C-p>` | Normal | Find files tracked by git |
| `<leader>ps` | Normal | Grep search (type a search term) |
| `<leader>pws` | Normal | Search for the word under cursor |
| `<leader>pWs` | Normal | Search for the WORD under cursor (includes special chars) |
| `<leader>vh` | Normal | Search vim help tags |

## LSP (Language Server)

| Key | Mode | What it does |
|-----|------|-------------|
| `gd` | Normal | Go to definition |
| `K` | Normal | Show hover documentation |
| `<leader>vws` | Normal | Search workspace symbols |
| `<leader>vd` | Normal | Show diagnostics in floating window |
| `<leader>vca` | Normal | Open code actions menu |
| `<leader>vrr` | Normal | Show all references |
| `<leader>vrn` | Normal | Rename symbol |
| `<C-h>` | Insert | Show signature help |
| `[d` | Normal | Go to next diagnostic |
| `]d` | Normal | Go to previous diagnostic |
| `<leader>zig` | Normal | Restart LSP server |

## Completion (nvim-cmp)

| Key | Mode | What it does |
|-----|------|-------------|
| `<C-p>` | Insert | Select previous completion item |
| `<C-n>` | Insert | Select next completion item |
| `<C-y>` | Insert | Confirm selected completion |
| `<C-Space>` | Insert | Trigger completion manually |

## Snippets (LuaSnip)

| Key | Mode | What it does |
|-----|------|-------------|
| `<C-s>e` | Insert | Expand snippet |
| `<C-s>;` | Insert/Select | Jump to next snippet placeholder |
| `<C-s>,` | Insert/Select | Jump to previous snippet placeholder |
| `<C-E>` | Insert/Select | Cycle through snippet choices |

## Go Error Handling Snippets

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>ee` | Normal | Insert `if err != nil { return err }` |
| `<leader>ea` | Normal | Insert `assert.NoError(err, "")` |
| `<leader>ef` | Normal | Insert `if err != nil { log.Fatalf(...) }` |
| `<leader>el` | Normal | Insert `if err != nil { .logger.Error(...) }` |

## Formatting (conform.nvim)

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>f` | Normal | Format current buffer |
| *(automatic)* | On save | Auto-formats using configured formatter or LSP fallback |

## Git (Fugitive)

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>gs` | Normal | Open git status window |
| `<leader>p` | Normal (in fugitive) | Git push |
| `<leader>P` | Normal (in fugitive) | Git pull with rebase |
| `<leader>t` | Normal (in fugitive) | Git push with upstream tracking |
| `gu` | Normal | Diffget from left side (merge conflicts) |
| `gh` | Normal | Diffget from right side (merge conflicts) |

## Debugging (DAP)

| Key | Mode | What it does |
|-----|------|-------------|
| `<F8>` | Normal | Continue execution |
| `<F10>` | Normal | Step over |
| `<F11>` | Normal | Step into |
| `<F12>` | Normal | Step out |
| `<leader>b` | Normal | Toggle breakpoint |
| `<leader>B` | Normal | Set conditional breakpoint (prompts for condition) |
| `<leader>dr` | Normal | Toggle REPL debug panel |
| `<leader>ds` | Normal | Toggle stacks debug panel |
| `<leader>dw` | Normal | Toggle watches debug panel |
| `<leader>db` | Normal | Toggle breakpoints debug panel |
| `<leader>dS` | Normal | Toggle scopes debug panel |
| `<leader>dc` | Normal | Toggle console debug panel |

## Testing (Neotest)

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>tr` | Normal | Run nearest test |
| `<leader>ts` | Normal | Run full test suite |
| `<leader>td` | Normal | Debug nearest test (uses DAP) |
| `<leader>tv` | Normal | Toggle test summary panel |
| `<leader>to` | Normal | Open test output |
| `<leader>ta` | Normal | Run all tests in current working directory |

## Trouble (Diagnostics)

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>tt` | Normal | Toggle trouble diagnostics window |
| `[t` | Normal | Jump to next trouble item |
| `]t` | Normal | Jump to previous trouble item |

## Quickfix & Location List

| Key | Mode | What it does |
|-----|------|-------------|
| `<C-k>` | Normal | Next quickfix item (centered) |
| `<C-j>` | Normal | Previous quickfix item (centered) |
| `<leader>k` | Normal | Next location list item (centered) |
| `<leader>j` | Normal | Previous location list item (centered) |

## Undo Tree

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>u` | Normal | Toggle undo tree visualizer |

## Zen Mode

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>zz` | Normal | Zen mode (90 char width, line numbers on) |
| `<leader>zZ` | Normal | Zen mode (80 char width, no line numbers) |

## Tmux Integration

| Key | Mode | What it does |
|-----|------|-------------|
| `<C-f>` | Normal | Open tmux-sessionizer in new tmux window |
| `<M-h>` | Normal | Tmux vertical split with sessionizer |
| `<M-H>` | Normal | New tmux window with sessionizer |

## URL Utilities (gachikuku custom)

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>ue` | Visual | URL encode selected text |
| `<leader>ud` | Visual | URL decode selected text |

## 99 (AI Coding Assistant)

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>9s` | Normal | Search with 99 |
| `<leader>9vv` | Visual | Send selection to 99 |
| `<leader>9vp` | Visual | Send selection to 99 with prompt |
| `<leader>9x` | Normal | Stop all in-flight requests |
| `<leader>9i` | Normal | Show 99 info |
| `<leader>9l` | Normal | View 99 logs |
| `<leader>9n` | Normal | Next request logs |
| `<leader>9p` | Normal | Previous request logs |

## Fun

| Key | Mode | What it does |
|-----|------|-------------|
| `<leader>ca` | Normal | Cellular automaton - make it rain! |

## Disabled

| Key | What it was |
|-----|-------------|
| `Q` | Disabled (was Ex mode - nobody wants that) |
