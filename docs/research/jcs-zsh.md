# Joshua Stein’s current public Zsh setup

**Scope and as of:** 2026-08-21 (UTC). This note examines every tracked file on the default `master` branch of [`jcs/dotfiles`](https://github.com/jcs/dotfiles), plus relevant `.zshrc` history. Joshua Stein’s contact page says “I am jcs … on GitHub” and links to [`github.com/jcs`](https://github.com/jcs) ([source](https://jcs.org/contact)). A fresh remote query resolved `master`/`HEAD` to [`dab17f34a1a840c2840a8d1e136e54f75d394943`](https://github.com/jcs/dotfiles/commit/dab17f34a1a840c2840a8d1e136e54f75d394943); the current source is the commit-pinned [`.zshrc`](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc). `.zshrc` is the only Zsh-named tracked file in this repository.

## Findings

### 1. Completion: no public `compinit`, but basic and targeted completion

**Direct evidence.** Stein added the modern completion initialization in 2012:

```zsh
autoload -Uz compinit
compinit
```

([historical `.zshrc` L107–L108](https://github.com/jcs/dotfiles/blob/ac9d93dcc37f377fa913985b397b0319a4ad49b2/.zshrc#L107-L108); [authored addition commit](https://github.com/jcs/dotfiles/commit/ac9d93dcc37f377fa913985b397b0319a4ad49b2)). Those lines were still present immediately before their removal ([L95–L96](https://github.com/jcs/dotfiles/blob/10803841b3c9e7199b1b8f329285c3c507b66e8c/.zshrc#L95-L96)).

Stein’s authored 2021 commit, [`d7735c5`](https://github.com/jcs/dotfiles/commit/d7735c508ede56bdfb55146f7dec193128bbf1c7), removed them. Its message says the “extensive tab completion stuff” was slow and sometimes broke proper completion (for example, `diff -u`), while “Normal file/dir tab completion still works”; the stated loss was SSH-host completion.

The current file has no `compinit`. It does selectively configure legacy `compctl` completion for `dd`:

```zsh
# do tab completion for dd
compctl -k '(if of conv ibs obs bs cbs files skip file seek count)' \
	-S '=' -x 's[if=], s[of=]' -f - 'C[0,conv=*,*] n[-1,,], s[conv=]' \
	-k '(ascii ebcdic ibm block unblock lcase ucase swap noerror sync)' \
	-q -S ',' - 'n[-1,=]' -X '<number>'  -- dd
```

([current `.zshrc` L95–L99](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L95-L99); [authored 2025 addition commit](https://github.com/jcs/dotfiles/commit/07128426d8c4d6527f31d8504e82fceba086a5d0)).

**Inference.** This is a deliberate lightweight arrangement: retain normal filename/directory completion, omit `compinit` and its richer command-specific system, then add a narrow `dd` rule. The `compctl` operands provide `dd` keyword, file, conversion-value, and numeric-value completion.

**Scoped absence.** At this revision, a repository-wide tracked-file search finds no `compinit`, `compdef`, `zstyle`, or `fpath` setup. A completion helper named `__git_files` remains ([L109–L112](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L109-L112)), but the public config does not initialize the modern completion system. This does **not** prove every machine lacks extra setup: `.zshrc` optionally sources untracked `~/.zshrc.local` ([L152–L154](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L152-L154)), and system startup files are outside the repository.

### 2. Exact current `PATH`

```zsh
export PATH=~/bin:~/go/bin:/usr/local/bin:/usr/local/sbin:/bin:/usr/bin:/sbin:/usr/sbin:/usr/X11R6/bin
```

([current `.zshrc` L18](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L18)).

**Direct evidence:** this replaces rather than extends the inherited `PATH`, in exactly the shown order. **Scoped absence:** no other tracked current file changes this shell assignment, but the later private `.zshrc.local` hook could do so.

### 3. Reverse search, history, and Tab

**Direct evidence:**

```zsh
unset HISTFILE
```

([L11](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L11); [authored change and rationale](https://github.com/jcs/dotfiles/commit/642b6c59797883ca765da36173cb3a380338bbcd))

```zsh
# zsh will try to use vi key bindings because of the vi $EDITOR, but i want
# emacs style for control+a/e, etc.
bindkey -e
```

([L29–L31](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L29-L31); [authored binding commit](https://github.com/jcs/dotfiles/commit/b36b9a1297036bc2c5611b1510cfe8d9a8819534))

```zsh
HISTSIZE=5000
```

([L70–L75](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L70-L75); [authored increase commit](https://github.com/jcs/dotfiles/commit/ca7d20d9f9e21f57b1ed4c7c6c792a3ecb5a19d4)).

**Inference from normal Zsh keymap/history behavior:** `bindkey -e` makes `Ctrl-R` reverse incremental history search and leaves Tab (`Ctrl-I`) as `expand-or-complete`. With `HISTFILE` unset, that search is useful within the current shell’s in-memory history, bounded by `HISTSIZE=5000`, but history is not persisted across sessions.

**Scoped absence:** the tracked config has no explicit `Ctrl-R` or Tab binding, no `SAVEHIST`, and no history-sharing/appending options. Its only later explicit key binding is `Ctrl-D` ([L78–L93](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc#L78-L93)).

## Minimal-config takeaways

A minimal configuration matching the public behavior is:

```zsh
unset HISTFILE
HISTSIZE=5000
bindkey -e
# Do not run compinit; normal file/directory Tab completion remains.
# Add the cited compctl block only if dd-specific completion is useful.
```

No explicit `Ctrl-R` or Tab bindings are needed under the normal Emacs keymap. For self-documenting overrides, `bindkey '^R' history-incremental-search-backward` and `bindkey '^I' expand-or-complete` are reasonable, but they are **not** lines from Stein’s public config.

## References

- Joshua Stein, [contact page](https://jcs.org/contact).
- [`jcs/dotfiles`](https://github.com/jcs/dotfiles), [repository metadata/default branch](https://api.github.com/repos/jcs/dotfiles), current [`master` revision](https://github.com/jcs/dotfiles/commit/dab17f34a1a840c2840a8d1e136e54f75d394943), and [commit-pinned `.zshrc`](https://github.com/jcs/dotfiles/blob/dab17f34a1a840c2840a8d1e136e54f75d394943/.zshrc).
- Authored completion commits: [`compinit` addition](https://github.com/jcs/dotfiles/commit/ac9d93dcc37f377fa913985b397b0319a4ad49b2), [`compinit` removal and rationale](https://github.com/jcs/dotfiles/commit/d7735c508ede56bdfb55146f7dec193128bbf1c7), and [`dd` completion](https://github.com/jcs/dotfiles/commit/07128426d8c4d6527f31d8504e82fceba086a5d0).
