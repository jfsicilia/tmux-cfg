#!/bin/sh
# Stamp @sess_idx on every session = its 1-based position in the
# byte-sorted (LC_ALL=C) session-name list. That is the same order tmux
# uses for `switch-client -n/-p` and that status-format[0] renders via
# `#{S/n:...}`, so the number shown in the status list matches both the
# prev/next navigation and the kanata `sessions`+1..9 combos.
#
# Driven from the session-created / session-closed / after-rename-session
# hooks in tmux.conf (plus one pass at config load).
n=0
tmux list-sessions -F '#{session_name}' | LC_ALL=C sort | while IFS= read -r s; do
	n=$((n + 1))
	tmux set-option -t "$s" @sess_idx "$n"
done

# Setting an option doesn't repaint the status line; without this the new
# indices wouldn't show until the next status-interval tick (15s).
tmux refresh-client -S
