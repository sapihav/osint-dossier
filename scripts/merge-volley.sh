#!/usr/bin/env bash
# merge-volley.sh — Phase 1 merge: collapse all volley-*.json envelopes into
# stages/01-seed.json with deduped rows + per-provider answers.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: merge-volley.sh <slug>

Reads ./osint-<slug>/volley-*.json (envelope shape), extracts citation rows,
deduplicates by canonical URL, writes ./osint-<slug>/stages/01-seed.json.
Stdout: {rows, deduped, answers}.
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
shopt -u nullglob
if [ ${#volleys[@]} -eq 0 ]; then
  echo "merge-volley: no volley-*.json under $work" >&2
  exit 1
fi

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
    tavily)
      rows=$(jq -c '
        ((.result.results // []) | map({
          source: "tavily",
          url: (.url // ""),
          title: (.title // ""),
          snippet: (.content // .snippet // "")
        })) // []' "$f" 2>/dev/null || echo '[]')
      ans=$(jq -c '
        if (.result.answer // null) != null
        then [{provider: "tavily", answer: .result.answer}]
        else []
        end' "$f" 2>/dev/null || echo '[]')
      ;;
    jina)
      # Shape unknown; try a few common paths, skip if nothing matches.
      rows=$(jq -c '
        ( (.result.results // .result.data // .result.citations // []) | map({
          source: "jina",
          url: (.url // .link // ""),
          title: (.title // ""),
          snippet: (.snippet // .description // .content // "")
        }) ) // []' "$f" 2>/dev/null || echo '[]')
      if [ "$rows" = "[]" ]; then
        echo "merge-volley: warning — jina envelope shape unrecognised in $base, skipped" >&2
      fi
      ans='[]'
      ;;
    *)
      echo "merge-volley: warning — unknown provider '$prov' in $base, skipped" >&2
      rows='[]'
      ans='[]'
      ;;
  esac

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

jq -cn \
  --argjson rows "$final_count" \
  --argjson deduped "$deduped_n" \
  --argjson answers "$ans_count" \
  '{rows:$rows, deduped:$deduped, answers:$answers}'
