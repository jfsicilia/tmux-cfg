#!/usr/bin/env bash
# sleeping.sh — list slept session names, one per line (for pickers/scripts).
set -euo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hibernate-lib.sh"
hib_list "$SLEEPING_DIR"
