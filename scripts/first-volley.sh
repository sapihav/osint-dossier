#!/usr/bin/env bash
# first-volley.sh — Phase 1 fan-out: launch up to 4 search CLIs in parallel,
# stagger 0.5 s, per-job 60 s timeout. Writes envelopes to ./osint-<slug>/.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: first-volley.sh <subject_name> [context_keyword...]

Runs perplexity, exa, jina, tavily in parallel (those with env vars set).
Each call: 60 s timeout, 0.5 s stagger.
Output: ./osint-<slug>/volley-<provider>.json
Stdout: JSON summary {volleys, ok, failed, files}.
Stderr: progress.

Exit 0 if >=1 volley succeeded, 1 if all failed.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ $# -eq 0 ]; then
  usage
  [ $# -eq 0 ] && exit 1 || exit 0
fi

subject="$1"; shift
context="$*"
query="$subject${context:+ $context}"

# slug: lowercase, ASCII, hyphens for runs of non-alnum
slug=$(printf '%s' "$subject" \
  | LC_ALL=C tr '[:upper:]' '[:lower:]' \
  | LC_ALL=C tr -c 'a-z0-9' '-' \
  | sed 's/--*/-/g; s/^-//; s/-$//')
[ -z "$slug" ] && { echo "first-volley: empty slug from subject" >&2; exit 1; }

work="./osint-$slug"
mkdir -p "$work"

# Portable per-job timeout. Backgrounds cmd, kills after N seconds if alive.
# Returns the cmd's exit code (124 if we killed it).
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  (
    # Watcher: sleep, then kill if still running.
    sleep "$secs"
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
    fi
  ) &
  local watcher=$!
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  # Stop the watcher if cmd finished first.
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  # If we got SIGTERM (143) or SIGKILL (137), normalise to 124.
  if [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then rc=124; fi
  return "$rc"
}

# Each launcher writes its envelope to $work/volley-<provider>.json,
# returns 0 on success, non-zero on failure/timeout.
launch_perplexity() {
  local out="$work/volley-perplexity.json"
  run_with_timeout 60 perplexity ask --model sonar "$query" --out "$out"
}
launch_exa() {
  local out="$work/volley-exa.json"
  run_with_timeout 60 exa answer "$query" --out "$out"
}
launch_jina() {
  local out="$work/volley-jina.json"
  # jina prints envelope on stdout; capture via redirect.
  # exec replaces the bash subshell so SIGTERM lands on the jina process directly.
  run_with_timeout 60 bash -c 'exec jina search "$1" >"$2"' _ "$query" "$out"
}
launch_tavily() {
  local out="$work/volley-tavily.json"
  run_with_timeout 60 tavily search "$query" --out "$out"
}

# Detect availability: binary present AND env var set.
available=()
have() {
  local bin="$1" var="$2"
  command -v "$bin" >/dev/null 2>&1 || return 1
  [ -n "${!var:-}" ] || return 1
  return 0
}
have perplexity PERPLEXITY_API_KEY && available+=(perplexity)
have exa        EXA_API_KEY        && available+=(exa)
have jina       JINA_API_KEY       && available+=(jina)
have tavily     TAVILY_API_KEY     && available+=(tavily)

if [ ${#available[@]} -eq 0 ]; then
  echo "first-volley: no search CLI available (binary + env var)" >&2
  printf '{"volleys":0,"ok":0,"failed":0,"files":[]}\n'
  exit 1
fi

echo "first-volley: subject='$subject' slug='$slug' providers=${available[*]}" >&2

# Launch with stagger; track pids and provider per pid.
pids=()
provs=()
files=()

for prov in "${available[@]}"; do
  case "$prov" in
    perplexity) launch_perplexity & ;;
    exa)        launch_exa        & ;;
    jina)       launch_jina       & ;;
    tavily)     launch_tavily     & ;;
  esac
  pids+=("$!")
  provs+=("$prov")
  files+=("$work/volley-$prov.json")
  echo "first-volley: launched $prov (pid $!)" >&2
  sleep 0.5
done

ok=0
failed=0
ok_files=()
for i in "${!pids[@]}"; do
  pid="${pids[$i]}"
  prov="${provs[$i]}"
  file="${files[$i]}"
  rc=0
  wait "$pid" || rc=$?
  if [ "$rc" -eq 0 ] && [ -s "$file" ]; then
    echo "first-volley: $prov OK" >&2
    ok=$((ok+1))
    ok_files+=("$file")
  else
    echo "first-volley: $prov FAILED (rc=$rc)" >&2
    failed=$((failed+1))
  fi
done

# Emit summary as JSON (jq for safety).
jq -cn \
  --argjson volleys "${#available[@]}" \
  --argjson ok "$ok" \
  --argjson failed "$failed" \
  --args \
  '{volleys:$volleys, ok:$ok, failed:$failed, files:$ARGS.positional}' \
  -- "${ok_files[@]}"

[ "$ok" -gt 0 ] || exit 1
exit 0
