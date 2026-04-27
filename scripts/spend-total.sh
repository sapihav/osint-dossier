#!/usr/bin/env bash
# spend-total.sh — sum spend.jsonl, count calls, group by provider.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spend-total.sh <slug>

Reads ./osint-<slug>/spend.jsonl and prints
{"total_usd": X.XXX, "calls": N, "providers": {"<provider>": N, ...}}.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ $# -eq 0 ]; then
  usage
  [ $# -eq 0 ] && exit 1 || exit 0
fi

slug="$1"
file="./osint-$slug/spend.jsonl"

if [ ! -f "$file" ]; then
  printf '{"total_usd":0,"calls":0,"providers":{}}\n'
  exit 0
fi

# Tolerate corrupt lines: parse each line independently, drop on parse failure.
jq -cR 'fromjson? // empty' "$file" | jq -cs '
  {
    total_usd: ( (map(.cost_usd // 0) | add // 0) | . * 1000 | round / 1000 ),
    calls: length,
    providers: ( group_by(.provider) | map({key: (.[0].provider // ""), value: length}) | from_entries )
  }
'
