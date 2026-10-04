#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:$PATH"
cd "$(dirname "$0")"
python3 -B tools/build.py coleco
