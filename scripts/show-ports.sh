#!/bin/sh
# Populates the window option @server_ports from a project's .server.ports file
# — one "name:port" pair per line, whitespace around name/:/port is ignored —
# so the pill in status-right can show it next to the clock (only when
# non-empty).
#
# Searched upward from the pane's cwd to $HOME, so a subdirectory of the
# project still finds it, e.g. .server.ports:
#   backend:8180
#   frontend:8181
#
# Usage:
#   show-ports.sh <window_id> <path>   stamp one window (from a hook, both
#                                       args format-expanded by tmux)
#   show-ports.sh                      stamp every window (config load)
#
# Driven from the after-select-window / after-new-window hooks in tmux.conf.

get_server_ports() {
    window_id="$1"
    dir="$2"
    ports=""
    # Try to find a .server.ports file in the current directory or any parent directory up to $HOME,
    # and read its contents into the ports variable, formatted as "name:port" pairs.
    while :; do
        if [ -f "$dir/.server.ports" ]; then
            ports=$(awk -F: '
				{
					name = $1; port = $2
					gsub(/[[:space:]]/, "", name)
					gsub(/[[:space:]]/, "", port)
					if (name != "" && port != "") printf "%s:%s ", name, port
				}
			' "$dir/.server.ports" | sed 's/ $//')
            break
        fi
        if [ "$dir" = "$HOME" ] || [ "$dir" = "/" ]; then
            break
        fi
        dir=$(dirname "$dir")
    done
    # As output, we set the window option @server_ports to the found ports string
    tmux set-option -t "$window_id" -w @server_ports "$ports"
}

if [ -n "$1" ]; then
    get_server_ports "$1" "$2"
else
    tmux list-windows -a -F '#{window_id} #{pane_current_path}' | while IFS= read -r line; do
        get_server_ports "${line%% *}" "${line#* }"
    done
fi

tmux refresh-client -S 2>/dev/null || true
