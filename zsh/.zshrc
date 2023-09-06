autoload -U colors && colors

eval "$(/opt/homebrew/bin/brew shellenv)"
export PATH="/opt/homebrew/bin:$PATH"

# ChatGBT as of generate that for linux and BSD compatability as luke's version didn't work (27/07/23).
# export PATH="$PATH:$(find ~/.local/bin -type d -exec printf '%s:' {} + | sed 's/:$//')"

# Variables
VIM="nvim"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export DOTFILES="$HOME/.dotfiles"
export CPPFLAGS="-I/opt/homebrew/opt/openjdk/include"
export GIT_EDITOR=$VIM

# let control+w only delete one directory of a path, not the whole word
export WORDCHARS='*?_[]~=&;!#$%^(){}'

bindkey -e

PS1="%m:%~%(!.#.$) "                 # prompt

# Aliases
alias grep="grep --color=always"
alias vim="$VIM"
