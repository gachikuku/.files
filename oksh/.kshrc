_PS1_BLUE="\\[\e[36m\\]"
_PS1_BOLD="\\[\e[1m\\]"
_PS1_CLEAR="\\[\e[0m\\]"
_PS1_GREEN="\\[\e[32m\\]"
_PS1_MAGENTA="\\[\e[35m\\]"
_PS1_RED="\\[\e[31m\\]"
_PS1_WHITE="\\[\e[37m\\]"
_PS1_YELLOW="\\[\e[33m\\]"

export PS1='$_PS1_YELLOW\xe2\x94\x8c$_PS1_RED[$_PS1_MAGENTA\u$_PS1_GREEN@$_PS1_RED]$_PS1_YELLOW---$_PS1_RED($_PS1_MAGENTA\w$_PS1_RED)$_PS1_YELLOW$_PS1_CLEAR\n$_PS1_YELLOW\xe2\x94\x94>$_PS1_CLEAR'

set -o emacs
