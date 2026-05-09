#!/usr/bin/env bash
# Unit tests for `scripts/check-tools.sh --json`.
# No network, no real CLIs — uses shim binaries on a synthesised PATH.
# Run: bash tests/scripts/test-check-tools-json.sh

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../scripts/check-tools.sh"

# Build a tmp shim dir holding executable no-op stubs for the requested bins.
make_shim_dir() {
  local dir
  dir="$(mktemp -d)"
  for bin in "$@"; do
    cat >"$dir/$bin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$dir/$bin"
  done
  printf '%s' "$dir"
}

# Run check-tools.sh in --json mode under a controlled PATH and env.
# $1 = shim dir, $2 = env-var assignments string, rest = positional args.
# Captures stdout (JSON) and stderr separately into globals so tests don't
# depend on stream-interleaving order.
#   RC          — exit code
#   JSON        — verbatim stdout (the JSON line)
#   STDERR      — verbatim stderr
run_json() {
  local shim_dir="$1"; shift
  local env_block="$1"; shift
  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)
  set +e
  env -i \
    PATH="$shim_dir:/usr/bin:/bin" \
    HOME="$HOME" \
    LANG="${LANG:-C}" \
    LC_ALL="${LC_ALL:-C}" \
    bash -c "$env_block bash \"\$0\" --json \"\$@\"" "$SCRIPT" "$@" \
    >"$stdout_file" 2>"$stderr_file"
  RC=$?
  set -e
  JSON=$(cat "$stdout_file")
  STDERR=$(cat "$stderr_file")
  rm -f "$stdout_file" "$stderr_file"
}

pass=0
fail=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass=$((pass + 1))
    printf '  ✓ %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  ✗ %s\n     expected: %s\n     actual:   %s\n' \
      "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) pass=$((pass + 1)); printf '  ✓ %s\n' "$label" ;;
    *) fail=$((fail + 1)); printf '  ✗ %s   (needle: %s)\n     haystack: %s\n' \
         "$label" "$needle" "$haystack" ;;
  esac
}

# ---------------------------------------------------------------------------
echo "Test 1: subject required when --json given with no args (artifact still emitted)"
shim=$(make_shim_dir)
run_json "$shim" "" ""
assert_eq "exit code 2" "2" "$RC"
assert_contains "stderr mentions 'subject required'" "subject required" "$STDERR"
assert_eq "JSON still emitted (subject_name empty)" "" \
  "$(printf '%s' "$JSON" | jq -r '.subject_name')"
assert_eq "JSON still emitted (slug empty)" "" \
  "$(printf '%s' "$JSON" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 2: empty slug rejected (artifact still emitted with subject preserved)"
shim=$(make_shim_dir)
run_json "$shim" "" "   "
assert_eq "exit code 2" "2" "$RC"
assert_contains "stderr mentions 'empty slug'" "empty slug" "$STDERR"
assert_eq "subject_name preserved" "   " \
  "$(printf '%s' "$JSON" | jq -r '.subject_name')"
assert_eq "slug empty" "" \
  "$(printf '%s' "$JSON" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 3: no search CLIs → has_search false, exit 1, artifact still emitted"
shim=$(make_shim_dir)  # no shims at all
run_json "$shim" "" "Jane Doe"
assert_eq "exit code 1" "1" "$RC"
assert_eq "schema_version" "1" "$(printf '%s' "$JSON" | jq -r '.schema_version')"
assert_eq "phase"          "0" "$(printf '%s' "$JSON" | jq -r '.phase')"
assert_eq "has_search"     "false" "$(printf '%s' "$JSON" | jq -r '.has_search')"
assert_eq "subject_name"   "Jane Doe" "$(printf '%s' "$JSON" | jq -r '.subject_name')"
assert_eq "slug"           "jane-doe" "$(printf '%s' "$JSON" | jq -r '.slug')"
assert_eq "context empty"  "[]" "$(printf '%s' "$JSON" | jq -c '.context')"
assert_eq "clis_available has only system tools" "0" \
  "$(printf '%s' "$JSON" | jq '.clis_available | map(select(. as $c | ["perplexity","exa","tvly","jina","parallel-cli","apify","brightdata"] | index($c))) | length')"
assert_eq "env_vars_set empty" "[]" "$(printf '%s' "$JSON" | jq -c '.env_vars_set')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 4: bin present but env var unset → CLI not counted as available"
shim=$(make_shim_dir perplexity)
run_json "$shim" "" "Jane Doe"
assert_eq "exit code 1 (no usable search)" "1" "$RC"
assert_eq "has_search false" "false" "$(printf '%s' "$JSON" | jq -r '.has_search')"
assert_eq "perplexity NOT in clis_available" "false" \
  "$(printf '%s' "$JSON" | jq -r '.clis_available | any(. == "perplexity")')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 5: bin + env var present → CLI counted, has_search true, exit 0"
shim=$(make_shim_dir perplexity)
run_json "$shim" "PERPLEXITY_API_KEY=sk-test " "Jane Doe" "Acme Corp" "Berlin"
assert_eq "exit code 0" "0" "$RC"
assert_eq "has_search true" "true" "$(printf '%s' "$JSON" | jq -r '.has_search')"
assert_eq "perplexity in clis_available" "true" \
  "$(printf '%s' "$JSON" | jq -r '.clis_available | any(. == "perplexity")')"
assert_eq "PERPLEXITY_API_KEY in env_vars_set" "true" \
  "$(printf '%s' "$JSON" | jq -r '.env_vars_set | any(. == "PERPLEXITY_API_KEY")')"
assert_eq "context propagates" '["Acme Corp","Berlin"]' \
  "$(printf '%s' "$JSON" | jq -c '.context')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 6: multiple search providers + scraper"
shim=$(make_shim_dir perplexity exa apify)
run_json "$shim" "PERPLEXITY_API_KEY=k EXA_API_KEY=k APIFY_TOKEN=t " "Jane Doe"
assert_eq "exit code 0" "0" "$RC"
assert_eq "perplexity in clis_available" "true" \
  "$(printf '%s' "$JSON" | jq -r '.clis_available | any(. == "perplexity")')"
assert_eq "exa in clis_available" "true" \
  "$(printf '%s' "$JSON" | jq -r '.clis_available | any(. == "exa")')"
assert_eq "apify in clis_available" "true" \
  "$(printf '%s' "$JSON" | jq -r '.clis_available | any(. == "apify")')"
assert_eq "tvly NOT in clis_available" "false" \
  "$(printf '%s' "$JSON" | jq -r '.clis_available | any(. == "tvly")')"
assert_eq "APIFY_TOKEN in env_vars_set" "true" \
  "$(printf '%s' "$JSON" | jq -r '.env_vars_set | any(. == "APIFY_TOKEN")')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 7: slug normalisation (mixed case + punctuation)"
shim=$(make_shim_dir perplexity)
run_json "$shim" "PERPLEXITY_API_KEY=k " "John Q. Public-Smith"
assert_eq "exit code 0" "0" "$RC"
assert_eq "slug normalised" "john-q-public-smith" \
  "$(printf '%s' "$JSON" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 8: ts is ISO 8601 UTC"
shim=$(make_shim_dir perplexity)
run_json "$shim" "PERPLEXITY_API_KEY=k " "Jane Doe"
ts=$(printf '%s' "$JSON" | jq -r '.ts')
case "$ts" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
    pass=$((pass+1)); echo "  ✓ ts matches ISO 8601 UTC pattern: $ts" ;;
  *)
    fail=$((fail+1)); echo "  ✗ ts pattern: $ts" ;;
esac
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 9: subject with embedded double-quote escapes correctly"
shim=$(make_shim_dir perplexity)
run_json "$shim" "PERPLEXITY_API_KEY=k " 'Jane "Q" Doe'
assert_eq "subject_name decoded" 'Jane "Q" Doe' \
  "$(printf '%s' "$JSON" | jq -r '.subject_name')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 10: control chars in subject get JSON-escaped"
shim=$(make_shim_dir perplexity)
# Embed a tab and a newline. jq -r decodes them back to the original bytes.
run_json "$shim" "PERPLEXITY_API_KEY=k " $'Tab\there\nNewline'
assert_eq "subject_name decodes to original (tab+newline)" $'Tab\there\nNewline' \
  "$(printf '%s' "$JSON" | jq -r '.subject_name')"
# The on-the-wire JSON must NOT contain a literal tab/newline inside the
# subject_name value — that would be invalid JSON. jq parsing it above
# proves validity; a raw grep confirms the escape sequence is on the wire.
assert_contains "raw JSON contains \\t escape" '\t' "$JSON"
assert_contains "raw JSON contains \\n escape" '\n' "$JSON"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 11: non-ASCII subject — JSON valid, subject preserved, slug empty, exit 2"
shim=$(make_shim_dir perplexity)
# Cyrillic input. Slug recipe (ASCII-only) yields empty slug → exit 2,
# but the artifact must still parse and the subject must round-trip.
run_json "$shim" "PERPLEXITY_API_KEY=k " "Іван Петренко"
assert_eq "exit code 2"          "2" "$RC"
assert_eq "subject_name preserved" "Іван Петренко" \
  "$(printf '%s' "$JSON" | jq -r '.subject_name')"
assert_eq "slug empty"           "" "$(printf '%s' "$JSON" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 12: apify env-var alternation — APIFY_API_TOKEN counts when APIFY_TOKEN unset"
shim=$(make_shim_dir perplexity apify)
run_json "$shim" "PERPLEXITY_API_KEY=k APIFY_API_TOKEN=alt " "Jane Doe"
assert_eq "exit code 0" "0" "$RC"
assert_eq "apify in clis_available" "true" \
  "$(printf '%s' "$JSON" | jq -r '.clis_available | any(. == "apify")')"
assert_eq "APIFY_API_TOKEN reported in env_vars_set" "true" \
  "$(printf '%s' "$JSON" | jq -r '.env_vars_set | any(. == "APIFY_API_TOKEN")')"
assert_eq "APIFY_TOKEN NOT in env_vars_set" "false" \
  "$(printf '%s' "$JSON" | jq -r '.env_vars_set | any(. == "APIFY_TOKEN")')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 13: subject with embedded newline — stderr stays single-line on empty-slug error"
shim=$(make_shim_dir perplexity)
# Slug pipeline collapses embedded newlines to nothing → empty slug → err=2.
# The stderr message must not contain a raw newline from the subject —
# otherwise log scrapers split one warning into multiple lines. The JSON
# itself still escapes \n correctly via json_escape (verified in Test 10).
# `$STDERR` is captured via `$(cat …)` which strips trailing newlines, so
# a properly-sanitised one-line message has ZERO interior newlines.
run_json "$shim" "PERPLEXITY_API_KEY=k " $'\n\n\n'
assert_eq "exit code 2" "2" "$RC"
interior_newlines=$(printf '%s' "$STDERR" | tr -cd '\n' | wc -c | tr -d ' ')
assert_eq "stderr has no interior newlines (subject sanitised)" "0" "$interior_newlines"
assert_contains "stderr mentions 'empty slug'" "empty slug" "$STDERR"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo ""
echo "Passed: $pass"
echo "Failed: $fail"
[ "$fail" -eq 0 ]
