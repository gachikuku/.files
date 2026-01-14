PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

# Add Homebrew
PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
PATH="/opt/homebrew/opt/ruby/bin:$PATH"
PATH="/opt/homebrew/opt/curl/bin:$PATH"
PATH="/opt/homebrew/opt/tree-sitter/bin:$PATH"

# Add user paths (highest priority)
PATH="$HOME/bin:$PATH"
PATH="$HOME/.local/bin:$PATH"
PATH="$HOME/go/bin:$PATH"
PATH="$HOME/cargo/bin:$PATH"

# Add other tools
PATH="/Library/TeX/texbin:$PATH"
PATH="$HOME/Developer/depot_tools:$PATH"

export PATH

# Environment variables
export EDITOR="nvim"
export GIT_EDITOR="nvim"
export BROWSER="chromium"
export DOTFILES="$HOME/.files"
export GPG_TTY="$(tty)"

# Go configuration
export GOPATH="$HOME/go"
export GOPROXY=direct
export GOSUMDB=off
export GOTELEMETRY=off
export GOTOOLCHAIN=local

# Rust configuration
export CARGO_HOME="$HOME/cargo"

# Homebrew compiler flags
export LDFLAGS="-L/opt/homebrew/opt/curl/lib"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include -I/opt/homebrew/opt/curl/include"

# Other settings
export RUBYOPT="rubygems"
export PIP_NO_SSL_VERIFY=1

# Emacs mode
set -o emacs

# Prompt
PS1='$(d=${PWD#$HOME}; [ "$d" != "$PWD" ] && d="~$d"; printf "\033[35m%s:%s\033[32m$ \033[0m" "$(hostname -s)" "${d:-$PWD}")'

# Aliases
[ -x "$(command -v nvim)" ] && alias vim="nvim" vimdiff="nvim -d"
alias ls="ls -l"
alias lynx="lynx --nocolor"
alias grep="grep --color=auto"
alias diff="diff --color=auto"
alias mus='mpv --ytdl-raw-options=yes-playlist=,no-check-certificates= --vid=no --ytdl-format=bestaudio'
alias vid='mpv --autofit=100%x100% --ytdl-raw-options=yes-playlist=,no-check-certificates=,write-automatic-subs=,sub-langs=en'
alias chra='chromium --proxy-server=127.0.0.1:8080 --proxy-bypass-list="<-loopback>" --disable-features=AutoupgradeEnabled,HttpsUpgrades,IsSitePerProcess --user-data-dir=/tmp/chromium'
alias rot13="tr 'A-Za-z' 'N-ZA-Mn-za-m'"
