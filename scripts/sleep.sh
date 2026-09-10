#!/usr/bin/env bash
# sleep.sh [session] — save the session, move its snapshot to persist/sleeping/,
# then kill it. No argument = the session you're attached to. Undo with awake.sh.
set -euo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hibernate-lib.sh"
hib_stash "$SLEEPING_DIR" slept "${1:-}"
