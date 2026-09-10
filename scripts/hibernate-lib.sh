#!/usr/bin/env bash
# hibernate-lib.sh — shared helpers for the session sleep / kill workflow.
# Source it; do not execute it directly.
#
# Model: tmux-persist already saves every session to its own "<name>_*" files
# under @persist-dir. To "sleep" (park) or "kill" (close) a session we save it,
# move those files into a subdirectory — persist/sleeping/ or persist/killed/ —
# and then kill the session. Those subdirs are invisible to `restore.sh all`,
# tmux-continuum's boot restore and the age-based snapshot pruning (all of which
# only glob "<persist-dir>/*_last" at the top level), so a stashed session stays
# exactly where it is until you explicitly bring it back with awake.sh /
# revive.sh.

set -euo pipefail
shopt -s nullglob

_hib_die() { printf 'tmux-hibernate: %s\n' "$*" >&2; exit 1; }

command -v tmux >/dev/null 2>&1 || _hib_die "tmux not found"

_hib_opt() { tmux show-option -gqv "$1" 2>/dev/null || true; }

# tmux-persist publishes these paths as read-only options; fall back to the
# vendored plugin location if it is not loaded.
PERSIST_SAVE=$(_hib_opt @persist-save-script-path)
PERSIST_RESTORE=$(_hib_opt @persist-restore-script-path)
: "${PERSIST_SAVE:=$HOME/.config/tmux/plugins/tmux-persist/scripts/save.sh}"
: "${PERSIST_RESTORE:=$HOME/.config/tmux/plugins/tmux-persist/scripts/restore.sh}"
[ -x "$PERSIST_SAVE" ]    || _hib_die "tmux-persist save.sh not found: $PERSIST_SAVE"
[ -x "$PERSIST_RESTORE" ] || _hib_die "tmux-persist restore.sh not found: $PERSIST_RESTORE"

# @persist-dir with the same expansion tmux-persist's helpers.sh applies.
_hib_raw=$(_hib_opt @persist-dir)
if [ -n "$_hib_raw" ]; then
	PERSIST_DIR=$(printf '%s\n' "$_hib_raw" |
		sed "s,\$HOME,$HOME,g; s,\$HOSTNAME,$(hostname),g; s,~,$HOME,g")
else
	PERSIST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/persist"
fi
[ -d "$PERSIST_DIR" ] || _hib_die "persist dir does not exist yet: $PERSIST_DIR"

SLEEPING_DIR="$PERSIST_DIR/sleeping"
KILLED_DIR="$PERSIST_DIR/killed"

# session name <-> on-disk name — mirrors tmux-persist (encode "%" then "/").
_hib_enc() { local s=${1//%/%25}; printf '%s' "${s//\//%2F}"; }
_hib_dec() { local s=${1//%2F//};  printf '%s' "${s//%25/%}"; }

hib_current_session() { tmux display-message -p '#{client_session}' 2>/dev/null || true; }

# Best-effort: move the attached client to the session. Never fails the caller
# (there may be no client attached, e.g. when run headless).
hib_switch() {
	if [ -n "${TMUX:-}" ]; then
		tmux switch-client -t "=$1" 2>/dev/null && return 0
	fi
	tmux attach-session -t "=$1" 2>/dev/null || true
}

hib_msg() { tmux display-message "tmux-hibernate: $1" 2>/dev/null || true; }

# workmux injects a "sidebar" pane (@workmux_role = sidebar) into every window.
# It's a view, not session content — saving it makes the snapshot's pane list
# and layout string collide with the sidebar workmux re-adds on restore, so pane
# positions and working dirs drift further on every sleep/awake cycle. Drop it
# before saving; workmux's own after-new-session / after-new-window hooks put it
# back after restore.
_hib_drop_sidebar() {
	local pid
	while read -r pid; do
		[ -n "$pid" ] && tmux kill-pane -t "$pid" 2>/dev/null
	done < <(tmux list-panes -s -t "=$1" \
		-F '#{?#{==:#{@workmux_role},sidebar},#{pane_id},}' 2>/dev/null)
	return 0
}

# Suspend workmux's after-new-session / after-new-window hook slots so they
# don't inject the sidebar into a window restore.sh is still building pane by
# pane (which throws off `select-layout` and scrambles pane cwds). Remembers
# each slot with its array index; pair with the restore below. This is a
# different concern from the after-split-window sidebar de-dup in tmux.conf.
_HIB_WM_HOOKS=""
_hib_wm_hooks_suspend() {
	_HIB_WM_HOOKS=""
	local slot cmd
	while read -r slot cmd; do
		case "$slot" in after-new-session\[*|after-new-window\[*) ;; *) continue ;; esac
		case "$cmd"  in *workmux*) ;; *) continue ;; esac
		tmux set-hook -gu "$slot"
		_HIB_WM_HOOKS+="${slot}"$'\t'"${cmd}"$'\n'
	done < <(tmux show-hooks -g 2>/dev/null)
}
_hib_wm_hooks_restore() {
	[ -n "$_HIB_WM_HOOKS" ] || return 0
	local slot cmd
	while IFS=$'\t' read -r slot cmd; do
		[ -n "$slot" ] && tmux set-hook -g "$slot" "$cmd"
	done <<<"$_HIB_WM_HOOKS"
	_HIB_WM_HOOKS=""
}

# hib_list <dir> — stashed session names in <dir>, one per line, tmux sort order.
hib_list() {
	local f b
	[ -d "$1" ] || return 0
	for f in "$1"/*_last; do
		b=${f##*/}
		printf '%s\n' "$(_hib_dec "${b%_last}")"
	done | LC_ALL=C sort
}

hib_is_stashed() { [ -e "$2/$(_hib_enc "$1")_last" ]; }

# hib_move <session> <src_dir> <dst_dir> — move every "<name>_*" file for the
# session; returns non-zero (moving nothing) when the source holds no snapshot.
hib_move() {
	local enc f moved=0
	enc=$(_hib_enc "$1")
	[ -e "$2/${enc}_last" ] || return 1
	mkdir -p "$3"
	for f in "$2/${enc}_last" "$2/${enc}_last.hash" "$2/${enc}_"????????T??????*; do
		[ -e "$f" ] || [ -L "$f" ] || continue
		mv -f "$f" "$3/" && moved=1
	done
	[ "$moved" = 1 ]
}

# hib_stash <dst_dir> <past-tense-verb> [session] — save, move to <dst_dir>, kill.
hib_stash() {
	local dst=$1 verb=$2 session=${3:-}
	[ -n "$session" ] || session=$(hib_current_session)
	[ -n "$session" ] || _hib_die "no session given and no attached session"
	tmux has-session -t "=$session" 2>/dev/null || _hib_die "no such session: $session"

	_hib_drop_sidebar "$session"
	"$PERSIST_SAVE" quiet "$session" >/dev/null 2>&1 || _hib_die "save failed: $session"
	hib_move "$session" "$PERSIST_DIR" "$dst" \
		|| _hib_die "saved, but found no snapshot to stash for: $session"
	tmux kill-session -t "=$session"
	# belt & braces: if continuum's timer or a close hook re-saved the session
	# in the move→kill window, sweep that snapshot into the stash too.
	hib_move "$session" "$PERSIST_DIR" "$dst" 2>/dev/null || true
	hib_msg "$verb $session"
}

# hib_reassert_processes <session> — safety net for tmux-persist's process
# restore, which relaunches each pane's program with `send-keys`: that races a
# slow interactive shell still sourcing its rc, and the keystrokes can be
# dropped, leaving a bare prompt. After the restore we wait for shells to
# settle, then re-send any allow-listed program still missing — via
# tmux-persist's own strategy, so `claude` still becomes `claude --continue`.
#
# workmux re-adds its sidebar as pane 1 after restore, shifting the real panes,
# so we can't trust saved pane indices; instead the Nth non-sidebar pane in a
# window is matched to the Nth saved pane of that window.
hib_reassert_processes() {
	local session=$1
	local plugin_dir=${PERSIST_SAVE%/scripts/save.sh}
	local allow shells='zsh bash sh dash ksh fish'
	allow=$(_hib_opt @persist-default-processes)
	[ -n "$allow" ] || allow='vi vim view nvim emacs man less more tail top htop claude codex copilot cursor-agent agy gemini opencode'

	local last="$PERSIST_DIR/$(_hib_enc "$session")_last"
	[ -e "$last" ] || return 0
	local tmp; tmp=$(mktemp -d) || return 0
	case "$(readlink "$last")" in
		*.tgz) tar xzf "$last" -C "$tmp" 2>/dev/null ;;
		*)     cp "$last" "$tmp/layout" 2>/dev/null ;;
	esac
	local layout="$tmp/layout"
	[ -f "$layout" ] || { rm -rf "$tmp"; return 0; }

	sleep "${HIB_REASSERT_DELAY:-2}"

	local win
	while read -r win; do
		local -a saved=() dirs=() live_ids=()
		local w idx d full pid role
		while IFS=$'\t' read -r _ _ w _ _ idx _ d _ _ full; do
			[ "$w" = "$win" ] || continue
			saved+=("${full#:}"); dirs+=("${d#:}")
		done < <(grep '^pane' "$layout")
		while IFS=$'\t' read -r pid role; do
			[ "$role" = sidebar ] && continue
			live_ids+=("$pid")
		done < <(tmux list-panes -t "=$session:$win" -F $'#{pane_id}\t#{@workmux_role}' 2>/dev/null)

		local i
		for i in "${!saved[@]}"; do
			full=${saved[i]}; d=${dirs[i]}; pid=${live_ids[i]:-}
			[ -n "$full" ] && [ -n "$pid" ] || continue
			local first=${full%% *}
			case " $allow " in *" $first "*) ;; *) continue ;; esac
			local live ppid
			live=$(tmux display-message -p -t "$pid" '#{pane_current_command}' 2>/dev/null) || continue
			ppid=$(tmux display-message -p -t "$pid" '#{pane_pid}' 2>/dev/null) || continue
			case " $shells " in *" $live "*) ;; *) continue ;; esac
			# idle at a prompt, not mid-launch (don't fire twice into a slow app)
			[ -z "$(pgrep -P "$ppid" 2>/dev/null)" ] || continue

			local strat="$plugin_dir/strategies/${first}_session.sh" cmd
			if [ -x "$strat" ] && [ "$(_hib_opt "@persist-strategy-$first")" = session ]; then
				cmd=$("$strat" "$full" "$d")
			else
				cmd=$full
			fi
			tmux send-keys -t "$pid" "$cmd" C-m
		done
		unset saved dirs live_ids
	done < <(grep '^window' "$layout" | cut -f3 | sort -un)

	rm -rf "$tmp"
}

# hib_unstash <src_dir> <past-tense-verb> [session] — move back, restore, switch.
# With no session, pick one with fzf.
hib_unstash() {
	local src=$1 verb=$2 session=${3:-}
	if [ -z "$session" ]; then
		command -v fzf >/dev/null 2>&1 || _hib_die "pass a session name (fzf not installed)"
		session=$(hib_list "$src" | fzf --prompt "$verb " --reverse --height 40% --no-multi) || return 0
	fi
	[ -n "$session" ] || return 0

	if tmux has-session -t "=$session" 2>/dev/null; then
		hib_switch "$session"
		return 0
	fi
	hib_is_stashed "$session" "$src" || _hib_die "no stashed session named: $session"
	hib_move "$session" "$src" "$PERSIST_DIR" || _hib_die "could not move snapshot back: $session"

	# workmux's after-new-session / after-new-window hooks fire while restore.sh
	# is still building the session and inject the sidebar into a half-built
	# window, scrambling pane order and working dirs. Suspend those hook slots
	# for the restore, then rebuild the sidebar once, cleanly, at the end.
	local rc=0
	_hib_wm_hooks_suspend
	"$PERSIST_RESTORE" "$session" >/dev/null 2>&1 || rc=$?
	_hib_wm_hooks_restore
	[ "$rc" = 0 ] || _hib_die "restore failed: $session"

	if command -v workmux >/dev/null 2>&1; then
		while read -r _w; do
			workmux _sidebar-sync --window "$_w" >/dev/null 2>&1 || true
		done < <(tmux list-windows -t "=$session" -F '#{window_id}' 2>/dev/null)
	fi

	hib_switch "$session"
	hib_reassert_processes "$session" || true
	hib_msg "$verb $session"
}
