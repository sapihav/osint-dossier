#!/usr/bin/env bash
# spend-add.sh — append one CLI call to ./osint-<slug>/spend.jsonl.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spend-add.sh <envelope.json> <slug>

Reads cost_usd / elapsed_ms / provider / command from a CLI envelope and
appends one JSONL line to ./osint-<slug>/spend.jsonl. Prints the line.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage; exit 0
fi

if [ $# -ne 2 ]; then
  usage >&2; exit 1
fi

envelope="$1"
slug="$2"
[ -f "$envelope" ] || { echo "spend-add: $envelope not found" >&2; exit 1; }

work="./osint-$slug"
mkdir -p "$work"
out="$work/spend.jsonl"

# ISO-8601 UTC; portable across BSD and GNU date.
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Tolerate non-JSON envelopes: warn + skip rather than abort the orchestrator.
if ! line=$(jq -c --arg ts "$ts" '
  # Pick a numeric cost from a candidate value: number passes through;
  # object with .total is unwrapped; anything else -> null.
  def asnum:
    if type == "number" then .
    elif type == "object" and (.total | type == "number") then .total
    else null
    end;
  {
    ts: $ts,
    provider: (.provider // ""),
    command:  (.command  // ""),
    cost_usd: (
      ( (.cost_usd                 | asnum)
        // (.result.cost_usd       | asnum)
        // (.result.costDollars    | asnum)
        // 0 )
    ),
    elapsed_ms: (.elapsed_ms // 0)
  }
' "$envelope" 2>/dev/null); then
  echo "spend-add: warning — could not parse envelope $envelope, skipping" >&2
  exit 0
fi

printf '%s\n' "$line" >> "$out"
printf '%s\n' "$line"
