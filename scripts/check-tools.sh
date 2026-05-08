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

# Requires bash >= 4 (`printf -v`, `${arr[@]+…}`, `read -r … <<<…`).
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_SH="$HERE/install.sh"

# shellcheck source=_slug.sh
. "$HERE/_slug.sh"

say() { printf '%s\n' "$*"; }

# Tool table — single source of truth for both modes.
# Each row: "<bin>|<env_var_spec>|<category>"
#   env_var_spec — empty (no env var required), or a colon-separated list
#                  of env-var names; the CLI counts as available if ANY of
#                  the listed vars is non-empty (matches SKILL.md Tool layer
#                  for `apify`: APIFY_TOKEN OR APIFY_API_TOKEN).
#   category     — search | scrape | shell
TOOLS=(
  "perplexity|PERPLEXITY_API_KEY|search"
  "exa|EXA_API_KEY|search"
  "tavily|TAVILY_API_KEY|search"
  "jina|JINA_API_KEY|search"
  "parallel-cli|PARALLEL_API_KEY|search"
  "apify|APIFY_TOKEN:APIFY_API_TOKEN|scrape"
  "brightdata|BRIGHTDATA_API_KEY|scrape"
  "jq||shell"
  "curl||shell"
)

# A CLI is "available" iff: binary on PATH AND (no env var required OR
# at least one env var in the colon-separated spec is non-empty). Both
# modes use this definition so the JSON artifact matches what the operator
# sees in the human report.
is_available() {
  local bin="$1" env_spec="$2"
  command -v "$bin" >/dev/null 2>&1 || return 1
  [ -z "$env_spec" ] && return 0
  local var
  while IFS= read -r var; do
    [ -n "${!var:-}" ] && return 0
  done < <(printf '%s\n' "$env_spec" | tr ':' '\n')
  return 1
}

# Return the FIRST set env-var name from a colon-separated spec, or empty.
# Used so `env_vars_set` reports the var the operator actually exported,
# not every alternate.
first_set_env() {
  local env_spec="$1" var
  [ -z "$env_spec" ] && return 0
  while IFS= read -r var; do
    if [ -n "${!var:-}" ]; then
      printf '%s' "$var"
      return 0
    fi
  done < <(printf '%s\n' "$env_spec" | tr ':' '\n')
  return 0
}

# ----- JSON mode --------------------------------------------------------------

# Hand-rolled JSON emitter: jq itself is one of the tools we check for, so
# the artifact must be emittable without jq. Inputs are CLI args (subject
# plus optional context tokens). Escapes: backslash, double-quote, and the
# named control chars (\b \f \n \r \t); other control chars 0x00–0x1F get
# \uXXXX. Multi-byte UTF-8 passes through unchanged (valid in JSON strings).
# json_escape — `'\\'` and `'\\\\'` here are deliberate bash-literal
# backslashes; shellcheck SC1003 (info-level) flags them but this is the
# right form for matching one literal `\` and emitting a `\\` JSON escape.
json_escape() {
  local s="$1" out="" i ch n
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:i:1}"
    case "$ch" in
      '\') out+='\\' ;;
      '"') out+='\"' ;;
      $'\b') out+='\b' ;;
      $'\f') out+='\f' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *)
        # Non-ASCII multi-byte chars in UTF-8 locales also fall here; their
        # codepoint is > 31, so they pass through unmodified. In a C locale
        # bash indexes by byte, and high bytes (>= 0x80) likewise pass through.
        # `printf '%d' "'$ch"` returns a signed value on some platforms when
        # the byte has the high bit set (0xD0 → -48), so mask to 8 bits before
        # the control-char check — otherwise high UTF-8 bytes would be
        # mistaken for control chars.
        printf -v n '%d' "'$ch"
        n=$(( n & 0xff ))
        if (( n < 32 )); then
          printf -v ch '\\u%04x' "$n"
        fi
        out+="$ch"
        ;;
    esac
  done
  printf '%s' "$out"
}

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

# Emit the Phase 0 stage artifact to stdout. Returns:
#   0  artifact written, has_search true
#   1  artifact written, has_search false
#   2  artifact written with empty subject_name and/or empty slug — caller
#      must treat as failure (cannot create work folder), but the file
#      remains valid JSON for diagnostic purposes.
emit_json() {
  local subject="${1:-}"
  [ $# -gt 0 ] && shift
  local -a context=("$@")
  local err=0

  if [ -z "$subject" ]; then
    say "check-tools.sh --json: subject required" >&2
    err=2
  fi

  # slug recipe is in scripts/_slug.sh (sourced at top of this file). Same
  # function is sourced by first-volley.sh, so the two scripts cannot drift.
  local slug=""
  if [ -n "$subject" ]; then
    slug=$(slug_from "$subject")
    if [ -z "$slug" ]; then
      # Sanitise subject for the stderr message — embedded newlines / CRs
      # would wrap the warning across lines and confuse log scrapers. The
      # JSON output itself escapes these correctly via json_escape.
      local subj_safe="${subject//$'\n'/ }"
      subj_safe="${subj_safe//$'\r'/ }"
      say "check-tools.sh --json: empty slug from subject '$subj_safe'" >&2
      err=2
    fi
  fi

  local -a clis_available=() env_vars_set=()
  local has_search=false
  local row bin env_spec category set_var
  for row in "${TOOLS[@]}"; do
    IFS='|' read -r bin env_spec category <<<"$row"
    if is_available "$bin" "$env_spec"; then
      clis_available+=("$bin")
      set_var=$(first_set_env "$env_spec")
      [ -n "$set_var" ] && env_vars_set+=("$set_var")
      [ "$category" = "search" ] && has_search=true
    fi
  done

  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # `${arr[@]+"${arr[@]}"}` expands to nothing when `arr` is empty, which
  # is what we want under `set -u` — bare `${arr[@]}` would error.
  printf '{"schema_version":"1","phase":0,'
  printf '"clis_available":%s,' "$(json_array "${clis_available[@]+"${clis_available[@]}"}")"
  printf '"env_vars_set":%s,' "$(json_array "${env_vars_set[@]+"${env_vars_set[@]}"}")"
  printf '"has_search":%s,' "$has_search"
  printf '"subject_name":"%s",' "$(json_escape "$subject")"
  printf '"context":%s,' "$(json_array "${context[@]+"${context[@]}"}")"
  printf '"slug":"%s",' "$(json_escape "$slug")"
  printf '"ts":"%s"}\n' "$ts"

  if [ "$err" -ne 0 ]; then
    return "$err"
  fi
  [ "$has_search" = true ] || return 1
  return 0
}

if [ "${1:-}" = "--json" ]; then
  shift
  # Use `|| true` to keep `set -e` from short-circuiting before we capture
  # emit_json's distinct exit codes (0 / 1 / 2).
  emit_json "$@" || exit $?
  exit 0
fi

# ----- Human-readable mode ----------------------------------------------------

# Print the install command for a binary by delegating to install.sh.
# Empty string if install.sh doesn't know about it (e.g. jq, curl).
hint_for() {
  local bin="$1"
  [ -x "$INSTALL_SH" ] || return 0
  bash "$INSTALL_SH" --line "$bin" 2>/dev/null || true
}

check_bin() {
  local bin="$1" env_spec="${2:-}"
  if command -v "$bin" >/dev/null 2>&1; then
    if [ -n "$env_spec" ] && ! is_available "$bin" "$env_spec"; then
      # Build a human-readable list of the env-var names from the spec
      # ("FOO" or "FOO or BAR") so the colon syntax never leaks.
      local pretty="${env_spec//:/ or \$}"
      say "  ⚠  $bin — installed, but \$$pretty is not set"
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
check_bin apify        APIFY_TOKEN:APIFY_API_TOKEN
check_bin brightdata   BRIGHTDATA_API_KEY

say ""
say "Shell helpers:"
check_bin jq ""
check_bin curl ""

say ""
has_search=0
for row in "${TOOLS[@]}"; do
  IFS='|' read -r bin env_spec category <<<"$row"
  [ "$category" = "search" ] || continue
  if is_available "$bin" "$env_spec"; then
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
