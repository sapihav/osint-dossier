#!/usr/bin/env bash
# merge-volley.sh — Phase 1 merge: collapse all volley-*.json envelopes into
# stages/01-seed.json with deduped rows + per-provider answers.
#
# R24: also emit stages/01-volley-status.json aggregating per-provider
# attempt records (from first-volley.sh's volley-<prov>.status.json) plus
# the merge-side accept/reject reason. Operator-visible drop surface.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: merge-volley.sh <slug>

Reads ./osint-<slug>/volley-*.json (envelope shape), extracts citation rows,
deduplicates by canonical URL, writes ./osint-<slug>/stages/01-seed.json.
Also writes ./osint-<slug>/stages/01-volley-status.json with per-provider
{launched, exit_code, written_bytes, merged, reason}.
Stdout: {rows, deduped, answers, merged_providers, dropped_providers}.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ] || [ $# -eq 0 ]; then
  usage
  [ $# -eq 0 ] && exit 1 || exit 0
fi

slug="$1"
work="./osint-$slug"
[ -d "$work" ] || { echo "merge-volley: $work not found" >&2; exit 1; }
mkdir -p "$work/stages"

# Find volley files.
shopt -s nullglob
volleys=( "$work"/volley-*.json )
status_files=( "$work"/volley-*.status.json )
shopt -u nullglob
if [ ${#volleys[@]} -eq 0 ]; then
  echo "merge-volley: no volley-*.json under $work" >&2
  exit 1
fi

# volley-*.json glob also matches volley-*.status.json — strip those.
filtered=()
for f in "${volleys[@]}"; do
  case "$f" in
    *.status.json) ;;
    *) filtered+=("$f") ;;
  esac
done
volleys=("${filtered[@]}")

# Canonicalise URL: lowercase host, drop trailing slash, drop ?utm_* params.
# Implemented as a jq function (kept simple — handles common cases).
JQ_CANON='
def canon_url:
  . as $u
  | ($u | capture("^(?<scheme>[a-zA-Z]+)://(?<host>[^/?#]+)(?<path>[^?#]*)(?<query>\\?[^#]*)?(?<frag>#.*)?$") // null) as $p
  | if $p == null then ($u // "") | ascii_downcase
    else
      ( ($p.scheme | ascii_downcase) | (if . == "http" then "https" else . end) ) as $s
      | ( $p.host  | ascii_downcase ) as $h
      | ( $p.path // "" ) as $pa
      | ( ($p.query // "") | ltrimstr("?")
          | split("&")
          | map(select(length > 0 and (startswith("utm_") | not)))
          | join("&") ) as $q
      | ( if $pa == "" then "/" else $pa end ) as $pa2
      | ( $pa2 | sub("/+$"; "") ) as $pa3
      | ( if $pa3 == "" then "/" else $pa3 end ) as $pa4
      | $s + "://" + $h + $pa4 + ( if $q == "" then "" else "?" + $q end )
    end;
'

merged_from=()
all_rows='[]'
all_answers='[]'

# Per-provider merge outcome: accepted | rejected:<reason>
declare -A merge_outcome
declare -A merge_rows_count

for f in "${volleys[@]}"; do
  base=$(basename "$f")
  merged_from+=("$base")
  prov=$(basename "$f" .json)
  prov="${prov#volley-}"

  # Per-provider extraction. Default-shape rows: {source, url, title, snippet}.
  case "$prov" in
    perplexity)
      rows=$(jq -c '
        ((.result.citations // []) | map({
          source: "perplexity",
          url: (.url // ""),
          title: (.title // ""),
          snippet: (.snippet // "")
        })) // []' "$f" 2>/dev/null || echo '[]')
      ans=$(jq -c '
        if (.result.answer // null) != null
        then [{provider: "perplexity", answer: .result.answer}]
        else []
        end' "$f" 2>/dev/null || echo '[]')
      ;;
    exa)
      rows=$(jq -c '
        ((.result.citations // []) | map({
          source: "exa",
          url: (.url // ""),
          title: (.title // ""),
          snippet: (.snippet // "")
        })) // []' "$f" 2>/dev/null || echo '[]')
      ans=$(jq -c '
        if (.result.answer // null) != null
        then [{provider: "exa", answer: .result.answer}]
        else []
        end' "$f" 2>/dev/null || echo '[]')
      ;;
    tvly)
      rows=$(jq -c '
        ((.result.results // []) | map({
          source: "tvly",
          url: (.url // ""),
          title: (.title // ""),
          snippet: (.content // .snippet // "")
        })) // []' "$f" 2>/dev/null || echo '[]')
      ans=$(jq -c '
        if (.result.answer // null) != null
        then [{provider: "tvly", answer: .result.answer}]
        else []
        end' "$f" 2>/dev/null || echo '[]')
      ;;
    jina)
      # Envelope (post-R24 wrap): {result:{results:[{title,url,snippet,engine}]}}.
      # Older raw shapes also probed for backwards compat.
      rows=$(jq -c '
        ( (.result.results // .result.data // .result.citations // []) | map({
          source: "jina",
          url: (.url // .link // ""),
          title: (.title // ""),
          snippet: (.snippet // .description // .content // "")
        }) ) // []' "$f" 2>/dev/null || echo '[]')
      if [ "$rows" = "[]" ]; then
        echo "merge-volley: warning — jina envelope shape unrecognised in $base, skipped" >&2
        merge_outcome[$prov]="rejected:envelope-shape-unrecognised"
      fi
      ans='[]'
      ;;
    *)
      echo "merge-volley: warning — unknown provider '$prov' in $base, skipped" >&2
      rows='[]'
      ans='[]'
      merge_outcome[$prov]="rejected:unknown-provider"
      ;;
  esac

  rcount=$(jq 'length' <<<"$rows")
  merge_rows_count[$prov]=$rcount
  if [ -z "${merge_outcome[$prov]:-}" ]; then
    if [ "$rcount" -gt 0 ] || [ "$ans" != "[]" ]; then
      merge_outcome[$prov]="accepted"
    else
      merge_outcome[$prov]="rejected:no-rows-no-answer"
    fi
  fi

  all_rows=$(jq -c --argjson a "$all_rows" --argjson b "$rows" -n '$a + $b')
  all_answers=$(jq -c --argjson a "$all_answers" --argjson b "$ans" -n '$a + $b')
done

# Dedup by canonical URL. Keep first occurrence.
deduped=$(jq -c "$JQ_CANON"'
  map(select((.url // "") != ""))
  | map(. + {_k: (.url | canon_url)})
  | unique_by(._k)
  | map(del(._k))
' <<<"$all_rows")

raw_count=$(jq 'length' <<<"$all_rows")
final_count=$(jq 'length' <<<"$deduped")
ans_count=$(jq 'length' <<<"$all_answers")
deduped_n=$((raw_count - final_count))

# Build merged_from JSON array.
mf_json=$(printf '%s\n' "${merged_from[@]}" | jq -R . | jq -cs .)

jq -n \
  --argjson rows "$deduped" \
  --argjson answers "$all_answers" \
  --argjson merged_from "$mf_json" \
  '{schema_version: "1", merged_from: $merged_from, rows: $rows, answers: $answers}' \
  > "$work/stages/01-seed.json"

# ---- R24: build stages/01-volley-status.json ----
# Combine per-provider attempt records (from first-volley.sh) with merge outcome.
# Universe of providers = union(status files, volley files we processed).

declare -A seen_provs
status_rows='[]'

# 1) Providers that left a status file.
for sf in "${status_files[@]}"; do
  base=$(basename "$sf")
  # status filename: volley-<prov>.status.json
  pname="${base#volley-}"
  pname="${pname%.status.json}"
  seen_provs[$pname]=1

  outcome="${merge_outcome[$pname]:-rejected:no-volley-file}"
  rcount="${merge_rows_count[$pname]:-0}"

  row=$(jq -c \
    --arg outcome "$outcome" \
    --argjson merged_rows "$rcount" \
    '. + {merge_outcome: $outcome, merged_rows: $merged_rows}' \
    "$sf" 2>/dev/null) || row='{}'
  status_rows=$(jq -c --argjson a "$status_rows" --argjson b "$row" -n '$a + [$b]')
done

# 2) Providers that left a volley file but no status file (e.g. legacy / manual run).
for prov in "${!merge_outcome[@]}"; do
  [ "${seen_provs[$prov]:-}" = "1" ] && continue
  outcome="${merge_outcome[$prov]}"
  rcount="${merge_rows_count[$prov]:-0}"
  row=$(jq -n \
    --arg prov "$prov" \
    --arg outcome "$outcome" \
    --argjson merged_rows "$rcount" \
    '{schema_version:"1", provider:$prov, launched:null,
      exit_code:null, written_bytes:null, stderr_tail:"",
      merge_outcome:$outcome, merged_rows:$merged_rows}')
  status_rows=$(jq -c --argjson a "$status_rows" --argjson b "$row" -n '$a + [$b]')
done

# Sort by provider name for stable output.
status_rows=$(jq -c 'sort_by(.provider)' <<<"$status_rows")

merged_n=$(jq '[.[] | select(.merge_outcome == "accepted")] | length' <<<"$status_rows")
dropped_n=$(jq '[.[] | select(.merge_outcome | startswith("rejected:"))] | length' <<<"$status_rows")

jq -n \
  --argjson providers "$status_rows" \
  '{schema_version:"1", providers:$providers}' \
  > "$work/stages/01-volley-status.json"

jq -cn \
  --argjson rows "$final_count" \
  --argjson deduped "$deduped_n" \
  --argjson answers "$ans_count" \
  --argjson merged_providers "$merged_n" \
  --argjson dropped_providers "$dropped_n" \
  '{rows:$rows, deduped:$deduped, answers:$answers,
    merged_providers:$merged_providers, dropped_providers:$dropped_providers}'
