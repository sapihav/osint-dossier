#!/usr/bin/env bash
# test-volley.sh — unit tests for first-volley.sh + merge-volley.sh.
# Mocks all four CLIs on PATH and asserts artifact shape, drop visibility,
# and jina envelope wrapping. Pure bash + jq, runs offline.
#
# Run: bash tests/scripts/test-volley.sh
# Exit 0 = all green, 1 = at least one failure.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
FIRST_VOLLEY="$REPO_ROOT/scripts/first-volley.sh"
MERGE_VOLLEY="$REPO_ROOT/scripts/merge-volley.sh"

pass=0
fail=0
fail_names=()

assert() {
  local name="$1" cond="$2"
  if eval "$cond"; then
    printf '  ok  %s\n' "$name"
    pass=$((pass+1))
  else
    printf '  FAIL %s   (cond: %s)\n' "$name" "$cond"
    fail=$((fail+1))
    fail_names+=("$name")
  fi
}

# Build a sandboxed PATH with mock CLIs. Each mock honours --out FILE for
# perplexity / exa / tavily; jina writes to stdout (matches real CLI).
make_mocks() {
  local mode="$1" mockdir="$2"
  mkdir -p "$mockdir"

  cat >"$mockdir/perplexity" <<EOF
#!/usr/bin/env bash
# args: ask --model sonar <query> --out <file>
out=""
for ((i=1; i<=\$#; i++)); do
  if [ "\${!i}" = "--out" ]; then
    j=\$((i+1)); out="\${!j}"
  fi
done
[ -n "\$out" ] || { echo "mock-perplexity: --out missing" >&2; exit 2; }
EOF
  case "$mode" in
    ok)
      cat >>"$mockdir/perplexity" <<'EOF'
cat > "$out" <<JSON
{"schema_version":"1","provider":"perplexity","command":"ask",
 "result":{"answer":"mock perplexity answer",
           "citations":[{"url":"https://example.com/p1","title":"P1","snippet":"s1"},
                        {"url":"https://example.com/p2","title":"P2","snippet":"s2"}]}}
JSON
exit 0
EOF
      ;;
    fail)
      cat >>"$mockdir/perplexity" <<'EOF'
echo "mock-perplexity: HTTP 429 rate limited" >&2
exit 1
EOF
      ;;
  esac
  chmod +x "$mockdir/perplexity"

  cat >"$mockdir/exa" <<'EOF'
#!/usr/bin/env bash
# args: answer <query> --out <file>
out=""
for ((i=1; i<=$#; i++)); do
  if [ "${!i}" = "--out" ]; then
    j=$((i+1)); out="${!j}"
  fi
done
[ -n "$out" ] || { echo "mock-exa: --out missing" >&2; exit 2; }
cat > "$out" <<JSON
{"schema_version":"1","provider":"exa","command":"answer",
 "result":{"answer":"mock exa answer",
           "citations":[{"url":"https://example.com/e1","title":"E1","snippet":""},
                        {"url":"https://example.com/p1","title":"E1-dup","snippet":""}]}}
JSON
exit 0
EOF
  chmod +x "$mockdir/exa"

  # jina: bare {results:[...]} on stdout — exercises the envelope-wrap path.
  cat >"$mockdir/jina" <<'EOF'
#!/usr/bin/env bash
# args: search --json <query>
cat <<JSON
{"results":[
  {"title":"J1","url":"https://example.com/j1","snippet":"jina s1","engine":"google"},
  {"title":"J2","url":"https://example.com/j2","snippet":"jina s2","engine":"google"}
]}
JSON
exit 0
EOF
  chmod +x "$mockdir/jina"

  # tavily: simulate a binary that writes nothing then exits non-zero —
  # this is the "silent drop" the issue describes.
  cat >"$mockdir/tavily" <<'EOF'
#!/usr/bin/env bash
echo "mock-tavily: connection timeout" >&2
exit 28
EOF
  chmod +x "$mockdir/tavily"
}

run_case() {
  local case_name="$1" perp_mode="$2" tmpdir
  tmpdir=$(mktemp -d -t volleytest.XXXXXX)
  # shellcheck disable=SC2064  # tmpdir must expand at trap-set time
  trap "rm -rf '$tmpdir'" RETURN

  local mocks="$tmpdir/bin"
  make_mocks "$perp_mode" "$mocks"

  # Run with sandboxed PATH so the real CLIs don't get hit. jq + bash + tr +
  # sed + sleep + wait must still resolve, so we keep /usr/bin + /bin + brew.
  local sandbox_path="$mocks:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  pushd "$tmpdir" >/dev/null || return 1

  PATH="$sandbox_path" \
  PERPLEXITY_API_KEY=stub \
  EXA_API_KEY=stub \
  JINA_API_KEY=stub \
  TAVILY_API_KEY=stub \
    bash "$FIRST_VOLLEY" "Test Subject" >/dev/null 2>&1 || true

  PATH="$sandbox_path" \
    bash "$MERGE_VOLLEY" "test-subject" >/dev/null 2>&1 || true

  local work="./osint-test-subject"
  local seed="$work/stages/01-seed.json"
  local stat="$work/stages/01-volley-status.json"

  echo "== $case_name =="

  assert "seed artifact exists" "[ -s '$seed' ]"
  assert "status artifact exists" "[ -s '$stat' ]"

  # jina envelope wrap: file must have .result.results, NOT bare .results.
  assert "jina envelope wrapped" \
    "jq -e '.result.results | type == \"array\"' '$work/volley-jina.json' >/dev/null"
  assert "jina bare .results stripped" \
    "jq -e 'has(\"results\") | not' '$work/volley-jina.json' >/dev/null"

  # 4 providers attempted, 4 status rows.
  assert "status has 4 providers" \
    "[ \"\$(jq '.providers | length' '$stat')\" = '4' ]"

  # exa + jina both accepted.
  assert "exa accepted" \
    "jq -e '.providers[] | select(.provider==\"exa\") | .merge_outcome == \"accepted\"' '$stat' >/dev/null"
  assert "jina accepted" \
    "jq -e '.providers[] | select(.provider==\"jina\") | .merge_outcome == \"accepted\"' '$stat' >/dev/null"

  # tavily silent drop must surface as rejected with non-zero exit + stderr.
  assert "tavily rejected (no volley file)" \
    "jq -e '.providers[] | select(.provider==\"tavily\") | .merge_outcome == \"rejected:no-volley-file\"' '$stat' >/dev/null"
  assert "tavily exit_code != 0" \
    "jq -e '.providers[] | select(.provider==\"tavily\") | .exit_code != 0' '$stat' >/dev/null"
  assert "tavily stderr_tail captured" \
    "jq -e '.providers[] | select(.provider==\"tavily\") | .stderr_tail | contains(\"timeout\")' '$stat' >/dev/null"

  # Perplexity branch depends on case.
  if [ "$perp_mode" = "ok" ]; then
    assert "perplexity accepted" \
      "jq -e '.providers[] | select(.provider==\"perplexity\") | .merge_outcome == \"accepted\"' '$stat' >/dev/null"
    # Dedup: perplexity emits example.com/p1; exa emits example.com/p1 (dup) + example.com/e1.
    # jina emits j1, j2. perplexity also emits p2. Total raw 6 rows; dedup drops 1 (p1 dup).
    assert "seed rows = 5 after dedup" \
      "[ \"\$(jq '.rows | length' '$seed')\" = '5' ]"
  else
    assert "perplexity rejected" \
      "jq -e '.providers[] | select(.provider==\"perplexity\") | .merge_outcome == \"rejected:no-volley-file\"' '$stat' >/dev/null"
    assert "perplexity stderr captured" \
      "jq -e '.providers[] | select(.provider==\"perplexity\") | .stderr_tail | contains(\"429\")' '$stat' >/dev/null"
  fi

  popd >/dev/null
  rm -rf "$tmpdir"
  trap - RETURN
}

run_case "case A — all upstream healthy except tavily" ok
run_case "case B — perplexity 429, tavily timeout" fail

echo
echo "================ summary ================"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fail_names[@]}"
  exit 1
fi
exit 0
