#!/usr/bin/env bash
# kill.sh [session] — save the session, move its snapshot to persist/killed/,
# then kill it. Like sleep.sh but a separate drawer for sessions you're closing
# rather than parking. No argument = the attached session. Undo with revive.sh.
set -euo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hibernate-lib.sh"
hib_stash "$KILLED_DIR" killed "${1:-}"
