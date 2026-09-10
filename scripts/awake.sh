#!/usr/bin/env bash
# awake.sh [session] — move a slept session's snapshot back to persist/, restore
# it, and switch to it. No argument = pick one with fzf.
set -euo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hibernate-lib.sh"
hib_unstash "$SLEEPING_DIR" awoke "${1:-}"
