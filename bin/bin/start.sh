#!/bin/sh

# Session 1: background (apps)
tmux new-session -d -s apps
tmux send-keys -t apps:0 'chra' Enter
tmux new-window -t apps
tmux send-keys -t apps:1 'discord' Enter
tmux new-window -t apps

# Open Safari on workspace 3
open -a Safari

# Session 2: main (mitmproxy + blank)
tmux new-session -d -s main -c ~/Developer/tools/mitmproxy
tmux send-keys -t main:0 'git pull && uv run mitmproxy' Enter
tmux new-window -t main

# Attach to main session, window 1 (blank)
tmux attach-session -t main:1
