PS1='$(d=${PWD#$HOME}; [ "$d" != "$PWD" ] && d="~$d"; printf "\033[35m%s:%s\033[32m$ \033[0m" "$(hostname -s)" "${d:-$PWD}")'
