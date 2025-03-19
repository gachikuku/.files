#!/bin/sh

# Have to learn plumbing!
# https://git.codemadness.org/randomcrap/file/config/scripts/plumb.sh.html

export SFEED_PLUMBER_INTERACTIVE=1
export SFEED_PLUMBER=plumb.sh
export SFEED_AUTOCMD="m"

if [ "$1" = "-u" ]; then
    sfeed_update
fi

sfeed_curses ~/.sfeed/feeds/*
