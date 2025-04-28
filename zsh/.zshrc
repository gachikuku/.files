autoload -U colors && colors

# ChatGBT as of generate that for linux and BSD compatability as luke's version didn't work (27/07/23).
# export PATH="$PATH:$(find ~/.local/bin -type d -exec printf '%s:' {} + | sed 's/:$//')"
# export PATH="$PATH:$(find ~/bin -type d -exec printf '%s:' {} + | sed 's/:$//')"
# Adds `~/.local/bin` to $PATH
# export PATH="$PATH:${$(find ~/.local/bin -type d -printf %p:)%%:}"
export PATH=~/bin:/usr/local/bin:/usr/local/sbin:/bin:/usr/bin:/sbin:/usr/sbin:/opt/homebrew/opt/coreutils/libexec/gnubin:/opt/homebrew/sbin:/opt/homebrew/bin:/opt/homebrew/opt/ruby/bin:~/go/bin:~/cargo/bin:~/.local/bin:~/Developer/depot_tools:$PATH

# env variables
export EDITOR="nvim"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export DOTFILES="$HOME/.files"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"
export GIT_EDITOR="nvim"
export BROWSER="chromium"
export RUBYOPT="rubygems"
export GOPATH="$HOME/go"
export CARGO_HOME="$HOME/cargo"
export LDFLAGS="-L/opt/homebrew/opt/curl/lib"
export CPPFLAGS="-I/opt/homebrew/opt/curl/include"
export PATH="/opt/homebrew/opt/curl/bin:$PATH"
export GPG_TTY="$(tty)"
export GOPROXY=direct
export GOSUMDB=off
export GOTELEMETRY=off
export GOTOOLCHAIN=local
export PIP_NO_SSL_VERIFY=1
export MANPAGER='vim +MANPAGER --not-a-term -'

# let control+w only delete one directory of a path, not the whole word
export WORDCHARS='*?_[]~=&;!#$%^(){}'

# Emacs keys
bindkey -e

# prompt
PS1="%F{13}%m:%~%(!.%F{2}#.%F{2}$)%f "

# Use neovim for vim if present.
[ -x "$(command -v nvim)" ] && alias vim="nvim" vimdiff="nvim -d"

# Aliases
alias ls="ls -lGFtr"
alias grep="grep --color=auto"
alias diff="diff --color=auto"
alias mus='mpv --ytdl-raw-options=yes-playlist=,no-check-certificates= --vid=no --ytdl-format=bestaudio'
alias vid='mpv --autofit=100%x100% --ytdl-raw-options=yes-playlist=,no-check-certificates=,write-automatic-subs=,sub-langs=en'
alias chra='chromium --proxy-server=127.0.0.1:8080 --proxy-bypass-list="<-loopback>" --disable-features=AutoupgradeEnabled,HttpsUpgrades,IsSitePerProcess --user-data-dir=/tmp/chromium'
alias rot13="tr 'A-Za-z' 'N-ZA-Mn-za-m'"
alias archopenssl="curl 'https://man.archlinux.org/man/libressl-openssl.1.en.txt' | less"

# Edit line in vim with Meta-e:
autoload edit-command-line; zle -N edit-command-line
bindkey '^[e' edit-command-line
bindkey -M vicmd '^[[P' vi-delete-char
bindkey -M vicmd '^[e' edit-command-line
bindkey -M visual '^[[P' vi-delete

# Basic auto/tab complete:
autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit
_comp_options+=(globdots)		# Include hidden files.

# Created by `pipx` on 2024-05-30 12:37:30
export PATH="$PATH:/Users/gachikuku/.local/bin"
if [ -f "/Users/gachikuku/.config/fabric/fabric-bootstrap.inc" ]; then . "/Users/gachikuku/.config/fabric/fabric-bootstrap.inc"; fi
