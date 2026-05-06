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
# $1 = shim dir, $2 = quoted env-var assignments string,
# remaining args = positional args to the script.
run_json() {
  local shim_dir="$1"; shift
  local env_block="$1"; shift
  local out rc
  set +e
  out=$(env -i \
    PATH="$shim_dir:/usr/bin:/bin" \
    HOME="$HOME" \
    LANG="${LANG:-C}" \
    LC_ALL="${LC_ALL:-C}" \
    bash -c "$env_block bash \"\$0\" --json \"\$@\"" "$SCRIPT" "$@" 2>&1)
  rc=$?
  set -e
  printf '%s\n%s' "$rc" "$out"
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

# Helper: extract just the last line of mixed stderr+stdout output. The script
# emits stderr first (on error), then JSON to stdout; combined they appear in
# that order under `2>&1`, so the JSON is always the final line.
last_line() { printf '%s\n' "$1" | tail -n 1; }

# ---------------------------------------------------------------------------
echo "Test 1: subject required when --json given with no args (artifact still emitted)"
shim=$(make_shim_dir)
result=$(run_json "$shim" "" "")
rc=$(printf '%s' "$result" | head -1)
out=$(printf '%s' "$result" | tail -n +2)
json=$(last_line "$out")
assert_eq "exit code 2" "2" "$rc"
case "$out" in
  *"subject required"*) pass=$((pass+1)); echo "  ✓ stderr mentions 'subject required'" ;;
  *) fail=$((fail+1)); echo "  ✗ stderr: $out" ;;
esac
assert_eq "JSON still emitted (subject_name empty)" "" \
  "$(printf '%s' "$json" | jq -r '.subject_name')"
assert_eq "JSON still emitted (slug empty)" "" \
  "$(printf '%s' "$json" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 2: empty slug rejected (artifact still emitted with subject preserved)"
shim=$(make_shim_dir)
result=$(run_json "$shim" "" "   ")
rc=$(printf '%s' "$result" | head -1)
out=$(printf '%s' "$result" | tail -n +2)
json=$(last_line "$out")
assert_eq "exit code 2" "2" "$rc"
case "$out" in
  *"empty slug"*) pass=$((pass+1)); echo "  ✓ stderr mentions 'empty slug'" ;;
  *) fail=$((fail+1)); echo "  ✗ stderr: $out" ;;
esac
assert_eq "subject_name preserved" "   " \
  "$(printf '%s' "$json" | jq -r '.subject_name')"
assert_eq "slug empty" "" \
  "$(printf '%s' "$json" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 3: no search CLIs → has_search false, exit 1, artifact still emitted"
shim=$(make_shim_dir)  # no shims at all
result=$(run_json "$shim" "" "Jane Doe")
rc=$(printf '%s' "$result" | head -1)
json=$(printf '%s' "$result" | tail -n +2)
assert_eq "exit code 1" "1" "$rc"
assert_eq "schema_version" "1" "$(printf '%s' "$json" | jq -r '.schema_version')"
assert_eq "phase"          "0" "$(printf '%s' "$json" | jq -r '.phase')"
assert_eq "has_search"     "false" "$(printf '%s' "$json" | jq -r '.has_search')"
assert_eq "subject_name"   "Jane Doe" "$(printf '%s' "$json" | jq -r '.subject_name')"
assert_eq "slug"           "jane-doe" "$(printf '%s' "$json" | jq -r '.slug')"
assert_eq "context empty"  "[]" "$(printf '%s' "$json" | jq -c '.context')"
assert_eq "clis_available has only system tools" "0" \
  "$(printf '%s' "$json" | jq '.clis_available | map(select(. as $c | ["perplexity","exa","tavily","jina","parallel-cli","apify","brightdata"] | index($c))) | length')"
assert_eq "env_vars_set empty" "[]" "$(printf '%s' "$json" | jq -c '.env_vars_set')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 4: bin present but env var unset → CLI not counted as available"
shim=$(make_shim_dir perplexity)
result=$(run_json "$shim" "" "Jane Doe")
rc=$(printf '%s' "$result" | head -1)
json=$(printf '%s' "$result" | tail -n +2)
assert_eq "exit code 1 (no usable search)" "1" "$rc"
assert_eq "has_search false" "false" "$(printf '%s' "$json" | jq -r '.has_search')"
assert_eq "perplexity NOT in clis_available" "false" \
  "$(printf '%s' "$json" | jq -r '.clis_available | any(. == "perplexity")')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 5: bin + env var present → CLI counted, has_search true, exit 0"
shim=$(make_shim_dir perplexity)
result=$(run_json "$shim" "PERPLEXITY_API_KEY=sk-test " "Jane Doe" "Acme Corp" "Berlin")
rc=$(printf '%s' "$result" | head -1)
json=$(printf '%s' "$result" | tail -n +2)
assert_eq "exit code 0" "0" "$rc"
assert_eq "has_search true" "true" "$(printf '%s' "$json" | jq -r '.has_search')"
assert_eq "perplexity in clis_available" "true" \
  "$(printf '%s' "$json" | jq -r '.clis_available | any(. == "perplexity")')"
assert_eq "PERPLEXITY_API_KEY in env_vars_set" "true" \
  "$(printf '%s' "$json" | jq -r '.env_vars_set | any(. == "PERPLEXITY_API_KEY")')"
assert_eq "context propagates" '["Acme Corp","Berlin"]' \
  "$(printf '%s' "$json" | jq -c '.context')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 6: multiple search providers + scraper"
shim=$(make_shim_dir perplexity exa apify)
result=$(run_json "$shim" "PERPLEXITY_API_KEY=k EXA_API_KEY=k APIFY_TOKEN=t " "Jane Doe")
rc=$(printf '%s' "$result" | head -1)
json=$(printf '%s' "$result" | tail -n +2)
assert_eq "exit code 0" "0" "$rc"
assert_eq "perplexity in clis_available" "true" \
  "$(printf '%s' "$json" | jq -r '.clis_available | any(. == "perplexity")')"
assert_eq "exa in clis_available" "true" \
  "$(printf '%s' "$json" | jq -r '.clis_available | any(. == "exa")')"
assert_eq "apify in clis_available" "true" \
  "$(printf '%s' "$json" | jq -r '.clis_available | any(. == "apify")')"
assert_eq "tavily NOT in clis_available" "false" \
  "$(printf '%s' "$json" | jq -r '.clis_available | any(. == "tavily")')"
assert_eq "APIFY_TOKEN in env_vars_set" "true" \
  "$(printf '%s' "$json" | jq -r '.env_vars_set | any(. == "APIFY_TOKEN")')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 7: slug normalisation (mixed case + punctuation)"
shim=$(make_shim_dir perplexity)
result=$(run_json "$shim" "PERPLEXITY_API_KEY=k " "John Q. Public-Smith")
rc=$(printf '%s' "$result" | head -1)
json=$(printf '%s' "$result" | tail -n +2)
assert_eq "exit code 0" "0" "$rc"
assert_eq "slug normalised" "john-q-public-smith" \
  "$(printf '%s' "$json" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 8: ts is ISO 8601 UTC"
shim=$(make_shim_dir perplexity)
result=$(run_json "$shim" "PERPLEXITY_API_KEY=k " "Jane Doe")
json=$(printf '%s' "$result" | tail -n +2)
ts=$(printf '%s' "$json" | jq -r '.ts')
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
result=$(run_json "$shim" "PERPLEXITY_API_KEY=k " 'Jane "Q" Doe')
json=$(printf '%s' "$result" | tail -n +2)
assert_eq "subject_name decoded" 'Jane "Q" Doe' \
  "$(printf '%s' "$json" | jq -r '.subject_name')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 10: control chars in subject get JSON-escaped"
shim=$(make_shim_dir perplexity)
# Embed a tab and a newline. jq -r will decode them back to the original bytes.
result=$(run_json "$shim" "PERPLEXITY_API_KEY=k " $'Tab\there\nNewline')
json=$(printf '%s' "$result" | tail -n +2)
assert_eq "subject_name decodes to original (tab+newline)" $'Tab\there\nNewline' \
  "$(printf '%s' "$json" | jq -r '.subject_name')"
# The on-the-wire JSON must NOT contain a literal tab/newline inside the
# subject_name value — that would be invalid JSON. jq parsing it via the
# previous assertion proves validity; a raw grep confirms the escape.
case "$json" in
  *'\t'*'\n'*) pass=$((pass+1)); echo "  ✓ raw JSON contains \\t and \\n escapes" ;;
  *) fail=$((fail+1)); echo "  ✗ raw JSON missing escapes: $json" ;;
esac
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo "Test 11: non-ASCII subject — JSON valid, subject preserved, slug empty, exit 2"
shim=$(make_shim_dir perplexity)
# Cyrillic input. Slug recipe (ASCII-only) yields empty slug → exit 2,
# but the artifact must still parse and the subject must round-trip.
result=$(run_json "$shim" "PERPLEXITY_API_KEY=k " "Іван Петренко")
rc=$(printf '%s' "$result" | head -1)
json=$(last_line "$(printf '%s' "$result" | tail -n +2)")
assert_eq "exit code 2"          "2" "$rc"
assert_eq "subject_name preserved" "Іван Петренко" \
  "$(printf '%s' "$json" | jq -r '.subject_name')"
assert_eq "slug empty"           "" "$(printf '%s' "$json" | jq -r '.slug')"
rm -rf "$shim"

# ---------------------------------------------------------------------------
echo ""
echo "Passed: $pass"
echo "Failed: $fail"
[ "$fail" -eq 0 ]
