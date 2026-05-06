#!/usr/bin/env bash
# check-tools.sh — Phase 0 preflight for the osint-dossier skill.
# Reports which CLIs and env-var keys are available. No network calls.
#
# Modes:
#   bash check-tools.sh                       # human-readable preflight
#   bash check-tools.sh --json <subject> [context...]
#                                              # emit Phase 0 stage artifact JSON
#
# Exit codes (both modes):
#   0  at least one search provider is usable
#   1  no search provider usable (artifact still written in --json mode)

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$HERE/install.sh"

# Tool table — single source of truth for both modes.
# Each row: "<bin>|<env_var>|<category>"
# category ∈ {search, scrape, shell}
TOOLS=(
  "perplexity|PERPLEXITY_API_KEY|search"
  "exa|EXA_API_KEY|search"
  "tavily|TAVILY_API_KEY|search"
  "jina|JINA_API_KEY|search"
  "parallel-cli|PARALLEL_API_KEY|search"
  "apify|APIFY_TOKEN|scrape"
  "brightdata|BRIGHTDATA_API_KEY|scrape"
  "jq||shell"
  "curl||shell"
)

# A CLI is "available" iff: binary on PATH AND (no env var required OR env var non-empty).
# Both modes use this definition so the JSON artifact matches what the operator sees.
is_available() {
  local bin="$1" env_var="$2"
  command -v "$bin" >/dev/null 2>&1 || return 1
  [ -z "$env_var" ] || [ -n "${!env_var:-}" ]
}

# ----- JSON mode --------------------------------------------------------------

emit_json() {
  local subject="${1:-}"
  [ $# -gt 0 ] && shift
  local -a context=("$@")

  if [ -z "$subject" ]; then
    echo "check-tools.sh --json: subject required" >&2
    return 2
  fi

  # slug recipe matches first-volley.sh: lowercase ASCII, runs of non-alnum → hyphen.
  local slug
  slug=$(printf '%s' "$subject" \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C tr -c 'a-z0-9' '-' \
    | sed 's/--*/-/g; s/^-//; s/-$//')
  if [ -z "$slug" ]; then
    echo "check-tools.sh --json: empty slug from subject '$subject'" >&2
    return 2
  fi

  local -a clis_available=() env_vars_set=()
  local has_search=false
  local row bin env_var category
  for row in "${TOOLS[@]}"; do
    IFS='|' read -r bin env_var category <<<"$row"
    if is_available "$bin" "$env_var"; then
      clis_available+=("$bin")
      [ -n "$env_var" ] && env_vars_set+=("$env_var")
      [ "$category" = "search" ] && has_search=true
    fi
  done

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Hand-rolled JSON emitter: jq itself is one of the tools we check for, so
  # the artifact must be emittable without jq. Inputs are CLI args (subject
  # plus optional context tokens). Backslash and double-quote get escaped;
  # UTF-8 passes through unchanged (valid in JSON strings).
  json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  json_array() {
    local first=1 item
    printf '['
    for item in "$@"; do
      [ $first -eq 1 ] || printf ','
      printf '"%s"' "$(json_escape "$item")"
      first=0
    done
    printf ']'
  }
  printf '{"schema_version":"1","phase":0,'
  printf '"clis_available":%s,' "$(json_array "${clis_available[@]+"${clis_available[@]}"}")"
  printf '"env_vars_set":%s,' "$(json_array "${env_vars_set[@]+"${env_vars_set[@]}"}")"
  printf '"has_search":%s,' "$has_search"
  printf '"subject_name":"%s",' "$(json_escape "$subject")"
  printf '"context":%s,' "$(json_array "${context[@]+"${context[@]}"}")"
  printf '"slug":"%s",' "$(json_escape "$slug")"
  printf '"ts":"%s"}\n' "$ts"

  [ "$has_search" = true ] || return 1
  return 0
}

if [ "${1:-}" = "--json" ]; then
  shift
  emit_json "$@"
  exit $?
fi

# ----- Human-readable mode ----------------------------------------------------

say() { printf '%s\n' "$*"; }

# Print the install command for a binary by delegating to install.sh.
# Empty string if install.sh doesn't know about it (e.g. jq, curl).
hint_for() {
  local bin="$1"
  [ -x "$INSTALL_SH" ] || return 0
  bash "$INSTALL_SH" --line "$bin" 2>/dev/null || true
}

check_bin() {
  local bin="$1" env_var="${2:-}"
  if command -v "$bin" >/dev/null 2>&1; then
    if [ -n "$env_var" ] && [ -z "${!env_var:-}" ]; then
      say "  ⚠  $bin — installed, but \$$env_var is not set"
    else
      say "  ✓  $bin"
    fi
  else
    local hint
    hint=$(hint_for "$bin")
    if [ -n "$hint" ]; then
      say "  ✗  $bin — not installed   ($hint)"
    else
      say "  ✗  $bin — not installed"
    fi
  fi
}

say "=== osint-dossier — tool preflight ==="
say ""

say "Search / retrieval:"
check_bin perplexity   PERPLEXITY_API_KEY
check_bin exa          EXA_API_KEY
check_bin tavily       TAVILY_API_KEY
check_bin jina         JINA_API_KEY
check_bin parallel-cli PARALLEL_API_KEY

say ""
say "Scraping / platform extraction:"
check_bin apify        APIFY_TOKEN
check_bin brightdata   BRIGHTDATA_API_KEY

say ""
say "Shell helpers:"
check_bin jq ""
check_bin curl ""

say ""
has_search=0
for row in "${TOOLS[@]}"; do
  IFS='|' read -r bin env_var category <<<"$row"
  [ "$category" = "search" ] || continue
  if is_available "$bin" "$env_var"; then
    has_search=1
    break
  fi
done

if [ "$has_search" -eq 0 ]; then
  say "⚠  No search CLI available. The skill will fall back to built-in"
  say "   WebSearch/WebFetch. Functionality is limited without a paid"
  say "   provider (Perplexity / Exa / Tavily / Jina)."
  say ""
  say "   To install everything the skill expects:"
  say "     bash scripts/install.sh"
  exit 1
fi

say "✓ at least one search CLI usable — preflight OK."
