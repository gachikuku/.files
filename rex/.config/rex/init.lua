-- Match the Ctrl+S prefix and pane navigation in the tmux configuration.
rex.bind("ctrl+s>h", "pane.focus.left")
rex.bind("ctrl+s>j", "pane.focus.down")
rex.bind("ctrl+s>k", "pane.focus.up")
rex.bind("ctrl+s>l", "pane.focus.right")
rex.bind("ctrl+s>ctrl+s", "pane.send_key", { key = "ctrl+s" })

require("last-tab")
rex.bind("ctrl+s>space", "last_visited_tab")

require("closed-tabs")
rex.bind("cmd+w", "retain_closed_tab")
rex.bind("cmd+shift+t", "reopen_closed_tab")
