# Keep PATH readable and duplicate-free. In Zsh, the path array is tied to PATH.
typeset -U path PATH
path=(
  # Personal tools (highest precedence).
  "$HOME/bin"
  "$HOME/.local/bin"
  "$HOME/go/bin"
  "$HOME/cargo/bin"
  "$HOME/.foundry/bin"
  "$HOME/Developer/depot_tools"

  # Homebrew and standalone toolchains.
  /opt/homebrew/opt/curl/bin
  /opt/homebrew/opt/openjdk/bin
  /opt/homebrew/opt/ruby/bin
  /opt/homebrew/opt/tree-sitter/bin
  /opt/homebrew/bin
  /opt/homebrew/sbin
  /Library/TeX/texbin

  # Prefer macOS utilities; scripts here rely on BSD date and related tools.
  /usr/local/bin
  /usr/local/sbin
  /bin
  /usr/bin
  /sbin
  /usr/sbin

  # GNU alternatives remain available without shadowing macOS utilities.
  /opt/homebrew/opt/coreutils/libexec/gnubin

  # Preserve valid paths supplied by macOS, Nix, or the caller.
  ${^path}(N-/)
)
export PATH

# Prompt colors.
autoload -U colors && colors

# Environment variables
export EDITOR="nvim"
export DOTFILES="$HOME/.files"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"
export GIT_EDITOR="nvim"
export BROWSER="open -a Safari"
export RUBYOPT="rubygems"
export GOPATH="$HOME/go"
export CARGO_HOME="$HOME/cargo"
export LDFLAGS="-L/opt/homebrew/opt/curl/lib"
export CPPFLAGS="-I/opt/homebrew/opt/curl/include"
export GPG_TTY="$(tty)"
export GOPROXY=direct
export GOSUMDB=off
export GOTELEMETRY=off
export GOTOOLCHAIN=local
export PIP_NO_SSL_VERIFY=1
export CLAUDE_DEBUG=1
#export MANPAGER="sh -c 'if [ -t 1 ]; then exec nvim +Man! -; else exec less -sR; fi'"
#export PAGER="sh -c 'if [ -t 1 ]; then exec nvim +Man! -; else exec less -sR; fi'"
#export AWS_PAGER=""

# let control+w only delete one directory of a path, not the whole word
export WORDCHARS='*?_[]~=&;!#$%^(){}'

# Emacs keys
bindkey -e

# Prevent accidental Ctrl-D from closing tmux panes, windows, or sessions.
if [[ -n "$TMUX" ]]; then
  setopt IGNORE_EOF

  tmux-ignore-eof() {
    if [[ -n "$BUFFER" ]]; then
      zle delete-char-or-list
    else
      zle -M 'Ctrl-D disabled in tmux; type exit to close this shell.'
    fi
  }

  zle -N tmux-ignore-eof
  bindkey '^D' tmux-ignore-eof
fi

# prompt
#PS1="%F{5}%m:%~%(!.%F{2}#.%F{2}$)%f "
PS1='%~%(!.#.$) '

# Use neovim for vim if present.
[ -x "$(command -v nvim)" ] && alias vim="nvim" vimdiff="nvim -d"

# Aliases

alias burp_sql="curl -s 'https://portswigger.net/web-security/sql-injection/cheat-sheet' | lynx -dump -stdin | sed -n '/^SQL injection cheat sheet$/,\$p' | less -i"
alias chra='chromium --proxy-server=127.0.0.1:8080 --proxy-bypass-list="<-loopback>" --disable-features=AutoupgradeEnabled,HttpsUpgrades,IsSitePerProcess --user-data-dir=/tmp/chromium'
alias codex='codex --yolo'
alias diff="diff --color=auto"
alias grep="grep --color=auto"
alias jwt_dool='docker run -it --network "host" --rm -v "${PWD}:/tmp" -v "${HOME}/.jwt_tool:/root/.jwt_tool" ticarpi/jwt_tool'
alias less='less -i'
alias ls="ls -lG"
alias lynx="lynx --nocolor"
alias man_openssl="curl -s 'https://man.archlinux.org/man/libressl-openssl.1.en.raw' | mandoc | nvim +Man! -"
alias man_r2="curl -s 'https://man.archlinux.org/man/radare2.1.en.raw' | mandoc | nvim +Man! -"
alias mus='mpv --ytdl-raw-options=yes-playlist=,no-check-certificates= --vid=no --ytdl-format=bestaudio'
alias pi='rehash; PI_OFFLINE=1 pi'
alias python='python3'
alias rot13="tr 'A-Za-z' 'N-ZA-Mn-za-m'"
alias shazzer="curl -s 'https://shazzer.co.uk/vectors/cheat-sheets' | lynx -dump -stdin | sed -n '/^Cheat sheets$/,\$p' | less -i"
alias vid='mpv --autofit=100%x100% --ytdl-raw-options=yes-playlist=,no-check-certificates=,write-automatic-subs=,sub-langs=en'

# Claude Code harness backed by GPT-5.6 Sol through the local CLIProxyAPI.
# ENABLE_TOOL_SEARCH=false disables dynamic MCP schema lookup, not WebSearch.
alias claude='ANTHROPIC_BASE_URL=http://127.0.0.1:8317 \
ANTHROPIC_AUTH_TOKEN=claudex-localhost-only \
CLAUDE_CODE_SUBAGENT_MODEL=gpt-5.6-sol \
CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1 \
CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=3 \
ENABLE_TOOL_SEARCH=false \
claude --model gpt-5.6-sol --effort high'

# Edit line in vim with Meta-e:
autoload edit-command-line; zle -N edit-command-line
bindkey '^[e' edit-command-line
bindkey -M vicmd '^[[P' vi-delete-char
bindkey -M vicmd '^[e' edit-command-line
bindkey -M visual '^[[P' vi-delete

# Joshua Stein's only custom completion: options and files for dd.
# Normal Tab completion remains Zsh's built-in expand-or-complete widget.
compctl -k '(if of conv ibs obs bs cbs files skip file seek count)' \
  -S '=' -x 's[if=], s[of=]' -f - 'C[0,conv=*,*] n[-1,,], s[conv=]' \
  -k '(ascii ebcdic ibm block unblock lcase ucase swap noerror sync)' \
  -q -S ',' - 'n[-1,=]' -X '<number>' -- dd

if [ -f "/Users/gachikuku/.config/fabric/fabric-bootstrap.inc" ]; then . "/Users/gachikuku/.config/fabric/fabric-bootstrap.inc"; fi

# uncomment when using claude-code
#export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
#export ANTHROPIC_AUTH_TOKEN=$(gopass show -o api/openrouter)
#export ANTHROPIC_API_KEY="" # Important: Must be explicitly empty
#export OPENROUTER_API_KEY=$(gopass show -o api/openrouter)
