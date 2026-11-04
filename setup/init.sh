#!/bin/bash
# Bash 3.2 compatible; the companion uses only Ruby 2.6+ standard libraries.
set -euo pipefail
SCRIPT_BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
command -v ruby >/dev/null 2>&1 || { echo 'Ruby 2.6+ is required' >&2; exit 1; }
exec ruby "${SCRIPT_BASE_DIR}/init.rb" "$@"
