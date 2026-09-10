#!/usr/bin/env bash
# tmux-layout.sh — build a tmux pane layout from a compact spec and run apps.
#
# Layout grammar
#   group  := "[" child (SEP child)* "]"    SEP is "|" (columns) or "/" (rows);
#                                            every SEP in one group must match.
#   child  := WEIGHT? group?                 a bare WEIGHT is a leaf pane;
#                                            WEIGHT followed by a group subdivides
#                                            that region recursively.
#   WEIGHT := positive integer (default 1)
#
#   "|"  side-by-side columns   -> tmux split-window -h
#   "/"  stacked rows           -> tmux split-window -v
#   Weights are relative:  [2|1]  => 2/3 and 1/3.   Whitespace is ignored.
#
# Commands are positional arguments, assigned to leaf panes in the order the
# leaves appear in the spec (depth-first, left to right). An empty string ("")
# leaves that pane at a shell.
#
#   tmux-layout.sh '[2|1[2/3]]' nvim htop 'journalctl -f'
#   tmux-layout.sh -s dev -d ~/proj '[1/1[1|1|1]]' '' nvim '' lazygit
#
# See usage() for options.

set -euo pipefail

die()  { printf 'tmux-layout: %s\n' "$*" >&2; exit 1; }
warn() { printf 'tmux-layout: %s\n' "$*" >&2; }

usage() {
	cat <<'EOF'
tmux-layout.sh — build a tmux pane layout from a compact spec and run apps.

Usage:
  tmux-layout.sh [-s NAME | -w NAME | -t TARGET] [-d DIR] [-b] LAYOUT [CMD...]

Options:
  -s NAME    build in a new session NAME
  -w NAME    build in a new window named NAME in the current session
  -t TARGET  build in an existing window/pane TARGET (its active pane is split)
  -d DIR     start directory for every pane (default: inherited)
  -b         do not switch to / focus the new window or session
  -h         show this help
Default target: a new unnamed window in the current session.
An empty LAYOUT ('') just makes one pane (handy with a single command).

Layout grammar:
  group  := "[" child (SEP child)* "]"     SEP = "|" columns  |  "/" rows
  child  := WEIGHT? group?                  WEIGHT alone   = one pane
                                            WEIGHT + group = subdivide that pane
  WEIGHT := positive integer (default 1)

  "|"  panes side by side  (tmux split -h)
  "/"  panes stacked       (tmux split -v)
  Weights are relative: [2|1] -> 2/3 and 1/3. Whitespace is ignored.

Commands are positional and fill leaf panes in spec order (depth-first,
left to right); "" leaves a pane at the shell.

Examples:
  tmux-layout.sh '[2|1[2/3]]' nvim htop 'journalctl -f'
  tmux-layout.sh -s dev -d ~/proj '[1/1[1|1|1]]' '' nvim '' lazygit
EOF
}

# ---- options --------------------------------------------------------------

mode="" name="" start_dir="" no_switch=0
setmode() { [ -z "$mode" ] || die "use only one of -s / -w / -t"; mode=$1; name=$2; }
while getopts ':s:w:t:d:bh' opt; do
	case $opt in
	s) setmode session "$OPTARG" ;;
	w) setmode window  "$OPTARG" ;;
	t) setmode target  "$OPTARG" ;;
	d) start_dir=$OPTARG ;;
	b) no_switch=1 ;;
	h) usage; exit 0 ;;
	:) die "option -$OPTARG requires an argument" ;;
	\?) die "unknown option -$OPTARG (see -h)" ;;
	esac
done
shift $((OPTIND - 1))

[ $# -ge 1 ] || { usage >&2; exit 1; }
SRC=$1; shift
CMDS=("$@")

command -v tmux >/dev/null 2>&1 || die "tmux not found"
[ "$mode" = session ] || [ -n "${TMUX:-}" ] || die "not inside tmux — pass -s NAME"

if [ -n "$start_dir" ]; then
	_abs=$(cd -- "$start_dir" 2>/dev/null && pwd) || die "no such directory: $start_dir"
	start_dir=$_abs
fi
sw_args=(); [ -n "$start_dir" ] && sw_args=(-c "$start_dir")

# ---- create the root pane ------------------------------------------------

case $mode in
session)
	tmux has-session -t "=$name" 2>/dev/null && die "session already exists: $name"
	root=$(tmux new-session -d -s "$name" -P -F '#{pane_id}' "${sw_args[@]}")
	;;
target)
	# TARGET is the pane to subdivide (a window resolves to its active pane).
	root=$(tmux display-message -p -t "$name" '#{pane_id}' 2>/dev/null) \
		|| die "no such target: $name"
	[ -z "$start_dir" ] || warn "-d does not change the cwd of the -t target pane"
	;;
window | "")
	# current session, explicitly, so it never lands elsewhere
	sess=$(tmux display-message -p '#{session_name}') || die "cannot determine current session"
	nm=(); [ "$mode" = window ] && nm=(-n "$name")
	root=$(tmux new-window -d -P -F '#{pane_id}' -t "=$sess:" "${nm[@]}" "${sw_args[@]}")
	;;
esac

# ---- parser + builder ---------------------------------------------------
# Globals: SRC, POS, LEAVES, sw_args. Panes are addressed by %id, stable
# across further splits, so we split a level fully, then recurse per child.

POS=0
INT=
LEAVES=()

_ws() { while [[ "${SRC:POS:1}" == [[:space:]] ]]; do POS=$((POS + 1)); done; }

# reads an integer at POS into INT ("" if none). Not $(...) — must mutate POS.
_int() {
	INT=
	while [[ "${SRC:POS:1}" == [0-9] ]]; do INT+=${SRC:POS:1}; POS=$((POS + 1)); done
}

# index just past the ']' matching the '[' at $1
_match() {
	local i=$1 depth=0 n=${#SRC} c
	while [ "$i" -lt "$n" ]; do
		c=${SRC:i:1}
		case $c in
		'[') depth=$((depth + 1)) ;;
		']') depth=$((depth - 1)); [ "$depth" -eq 0 ] && { printf '%s' $((i + 1)); return; } ;;
		esac
		i=$((i + 1))
	done
	die "layout: unbalanced '[' at position $1"
}

# _split <pane> <-h|-v> <weight>...  ->  echoes the resulting pane ids in order
_split() {
	local pane=$1 flag=$2; shift 2
	local -a w=("$@") out=()
	local n=${#w[@]} i total=0 rem pct cur new
	for i in "${w[@]}"; do total=$((total + i)); done
	rem=$total; cur=$pane
	for ((i = 0; i < n - 1; i++)); do
		# the new (right/bottom) pane keeps the remainder after peeling w[i]
		pct=$(((rem - w[i]) * 100 / rem))
		[ "$pct" -lt 1 ]  && pct=1
		[ "$pct" -gt 99 ] && pct=99
		new=$(tmux split-window -t "$cur" "$flag" -l "${pct}%" -P -F '#{pane_id}' "${sw_args[@]}") \
			|| die "split failed (pane too small?) while building '$SRC'"
		out+=("$cur"); cur=$new; rem=$((rem - w[i]))
	done
	out+=("$cur")
	printf '%s\n' "${out[*]}"
}

# _build_group <pane>  — POS must sit on the opening '['
_build_group() {
	local pane=$1
	[ "${SRC:POS:1}" = '[' ] || die "layout: expected '[' at position $POS"
	POS=$((POS + 1))

	local -a cw=() csub=()          # per child: weight, sub-start ('' = leaf)
	local sep= c w
	while :; do
		_ws
		case ${SRC:POS:1} in
		']' | '|' | '/') die "layout: empty pane at position $POS" ;;
		esac
		_int; w=$INT; [ -n "$w" ] || w=1
		[ "$w" -ge 1 ] || die "layout: weight must be >= 1 (position $POS)"
		_ws
		if [ "${SRC:POS:1}" = '[' ]; then
			csub+=("$POS"); POS=$(_match "$POS")
		else
			csub+=('')
		fi
		cw+=("$w")
		_ws
		c=${SRC:POS:1}
		case $c in
		']') POS=$((POS + 1)); break ;;
		'|' | '/')
			if [ -z "$sep" ]; then sep=$c
			elif [ "$sep" != "$c" ]; then die "layout: mixed '|' and '/' in one group (position $POS)"
			fi
			POS=$((POS + 1))
			;;
		'') die "layout: unexpected end of spec (missing ']')" ;;
		*) die "layout: unexpected '$c' at position $POS" ;;
		esac
	done

	local n=${#cw[@]} i save
	if [ "$n" -eq 1 ]; then
		if [ -n "${csub[0]}" ]; then
			save=$POS; POS=${csub[0]}; _build_group "$pane"; POS=$save
		else
			LEAVES+=("$pane")
		fi
		return
	fi

	[ -n "$sep" ] || die "layout: need '|' or '/' between panes (position $POS)"
	local flag=-h; [ "$sep" = '/' ] && flag=-v

	local ids; ids=$(_split "$pane" "$flag" "${cw[@]}") || exit 1
	local -a panes; read -ra panes <<<"$ids"
	[ "${#panes[@]}" -eq "$n" ] || die "internal: got ${#panes[@]} panes, expected $n"
	for ((i = 0; i < n; i++)); do
		if [ -n "${csub[i]}" ]; then
			save=$POS; POS=${csub[i]}; _build_group "${panes[i]}"; POS=$save
		else
			LEAVES+=("${panes[i]}")
		fi
	done
}

_ws
if [ "${SRC:POS:1}" = '[' ]; then
	_build_group "$root"
else
	_int                           # tolerate a bare weight / empty spec
	LEAVES+=("$root")
fi
_ws
[ "$POS" -ge "${#SRC}" ] || die "layout: trailing input at position $POS: '${SRC:POS}'"

# ---- run the commands -------------------------------------------------------

[ "${#CMDS[@]}" -le "${#LEAVES[@]}" ] \
	|| warn "${#CMDS[@]} commands for ${#LEAVES[@]} panes — extras ignored"

for i in "${!LEAVES[@]}"; do
	cmd=${CMDS[i]:-}
	[ -n "$cmd" ] || continue
	tmux send-keys -t "${LEAVES[i]}" -l -- "$cmd"
	tmux send-keys -t "${LEAVES[i]}" Enter
done

[ "${#LEAVES[@]}" -gt 0 ] && tmux select-pane -t "${LEAVES[0]}"

# ---- focus / attach -------------------------------------------------------

if [ "$no_switch" -eq 0 ]; then
	case $mode in
	session)
		if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$name"
		else exec tmux attach-session -t "=$name"
		fi
		;;
	target) tmux select-window -t "$name" ;;
	*)      tmux select-window -t "$root" ;;
	esac
fi
