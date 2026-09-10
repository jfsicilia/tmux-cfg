#!/usr/bin/env bash
# revive.sh [session] — move a killed session's snapshot back to persist/,
# restore it, and switch to it. No argument = pick one with fzf.
set -euo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hibernate-lib.sh"
hib_unstash "$KILLED_DIR" revived "${1:-}"
