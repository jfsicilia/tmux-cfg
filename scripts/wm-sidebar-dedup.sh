#!/bin/sh
# wm-sidebar-dedup.sh <window_id> — keep exactly one workmux sidebar pane in a
# window.
#
# `workmux sidebar on` installs after-new-session[99] and after-new-window[99]
# hooks that each run `workmux _sidebar-sync` on the fresh window. On a
# `new-session` BOTH fire for the first window; being `run-shell -b` they race,
# each passes its "does a sidebar already exist?" check, and each splits one in
# — so the session ends up with two. Hits every plain-`new-session` path
# (`sesh connect`, `workmux add`, `tmux new`, the sessmgr `n` binding).
#
# Wired from after-split-window[50] (workmux builds the sidebar with a split, so
# this fires right after the duplicate appears). It lives in a hook slot workmux
# never touches, so it survives `workmux sidebar off`/`on`, `workmux setup` and
# upgrades. Cheap no-op for ordinary splits.

win=${1:?usage: wm-sidebar-dedup.sh <window_id>}

# A pane is the workmux sidebar if it is tagged @workmux_role=sidebar OR was
# started as `… _sidebar-run`. The tag is a separate set-option that lands a
# beat after the split, so matching the start command too closes the window
# where a just-split duplicate is not tagged yet.
ids=$(tmux list-panes -t "$win" \
	-F '#{pane_id}|#{@workmux_role}|#{pane_start_command}' 2>/dev/null |
	awk -F'|' '$2 == "sidebar" || $3 ~ /_sidebar-run/ { print $1 }')

# shellcheck disable=SC2086
set -- $ids
[ "$#" -gt 1 ] || exit 0

shift   # keep the first (lowest pane index = the one workmux positioned)
for pid in "$@"; do
	tmux kill-pane -t "$pid" 2>/dev/null || true
done
