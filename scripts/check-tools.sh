#!/usr/bin/env bash
# check-tools.sh — Phase 0 preflight for the osint-dossier skill.
# Reports which CLIs and env-var keys are available. No network calls.
# Exits 0 if at least one search provider is usable; exits 1 otherwise.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$HERE/install.sh"

say() { printf '%s\n' "$*"; }

# Print the install command for a binary by delegating to install.sh.
# Empty string if install.sh doesn't know about it (e.g. jq, curl).
hint_for() {
  local bin="$1"
  [ -x "$INSTALL_SH" ] || return 0
  bash "$INSTALL_SH" --line "$bin" 2>/dev/null || true
}

ok=()
missing=()

check_bin() {
  # $1 = binary name; $2 = env var (optional)
  local bin="$1"; local env_var="${2:-}"
  if command -v "$bin" >/dev/null 2>&1; then
    if [ -n "$env_var" ] && [ -z "${!env_var:-}" ]; then
      say "  ⚠  $bin — installed, but \$$env_var is not set"
      missing+=("$bin")
    else
      say "  ✓  $bin"
      ok+=("$bin")
    fi
  else
    local hint
    hint=$(hint_for "$bin")
    if [ -n "$hint" ]; then
      say "  ✗  $bin — not installed   ($hint)"
    else
      say "  ✗  $bin — not installed"
    fi
    missing+=("$bin")
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
# Require at least one search provider
has_search=0
for bin in perplexity exa tavily jina parallel-cli; do
  if command -v "$bin" >/dev/null 2>&1; then
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
