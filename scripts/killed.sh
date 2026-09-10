#!/usr/bin/env bash
# killed.sh — list killed session names, one per line (for pickers/scripts).
set -euo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/hibernate-lib.sh"
hib_list "$KILLED_DIR"
