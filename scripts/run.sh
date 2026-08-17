#!/usr/bin/env bash
# Starts the real LÖVE app (Boot -> TitleScreen -> Field, the normal
# game flow -- no demo/state-skipping env vars) with the real script
# interpreter's shadow-run overlay enabled (MYSTICQUEST_SCRIPT_INTERPRETER=1,
# see VictorySequence.lua's own doc comment) and the dev ROM auto-loaded
# via MYSTICQUEST_ROM (see src/import/RomLocator.lua).
#
# Usage: scripts/run.sh [extra MYSTICQUEST_* env vars set by the caller
# still apply -- this script only sets defaults, real env always wins]
#
# Adjust MYSTICQUEST_ROM below (or export it yourself before calling
# this script) if your own ROM lives somewhere else.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

: "${MYSTICQUEST_ROM:=/Users/axon/Documents/development/gb/mysticquest_recomp/roms/extracted_mq/Mystic Quest (G) [!].gb}"
: "${MYSTICQUEST_SCRIPT_INTERPRETER:=1}"

if [ ! -f "$MYSTICQUEST_ROM" ]; then
  echo "run.sh: MYSTICQUEST_ROM not found at '$MYSTICQUEST_ROM'" >&2
  echo "        set MYSTICQUEST_ROM=/path/to/your.gb before calling this script." >&2
  exit 1
fi

export MYSTICQUEST_ROM
export MYSTICQUEST_SCRIPT_INTERPRETER

echo "run.sh: launching love . from $PROJECT_DIR"
echo "run.sh: MYSTICQUEST_ROM=$MYSTICQUEST_ROM"
echo "run.sh: MYSTICQUEST_SCRIPT_INTERPRETER=$MYSTICQUEST_SCRIPT_INTERPRETER"

cd "$PROJECT_DIR"
exec love .
