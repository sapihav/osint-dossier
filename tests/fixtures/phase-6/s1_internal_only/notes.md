# s1_internal_only — non-substitution + non-leak (criteria 2, 3)

Slot under test: `career_history` (`min_grade: B`, `min_sources: 2`,
`internal_counts: false` by default). Three Grade-I facts attached.
Even though `count >= min_sources`, none passes grade — so 0
eligible, `met: false`, `kind: low_grade`.

## What this asserts

**S1.1 non-substitution.** Phase 6 must NOT count Grade-I facts
toward `min_sources` for slots without `internal_counts: true`.
Three Grade-I facts on a `min_sources: 2` slot still produce
`met: false`.

**S1.2 non-leak.** The expected output contains no Grade-I claim
content — every Grade-I `claim` field in the input is `[REDACTED
— internal source, see Phase 2 promotion log]`, and the output's
`evidence[]` for `career_history` is `["fact_1", "fact_2", "fact_3"]`,
fact_id references only. Verify by hand: search the entire
expected-06-gaps.json for any substring of the input's `claim`
field — there must be zero matches.

## Replay walk-through

1. Load catalog (7 slots).
2. Attach: only `career_history` gets the three facts.
3. Eligibility: all three Grade-I + `internal_counts: false` →
   `passes_grade` returns false → 0 eligible.
4. Kind: facts attached, no fact passes grade → `low_grade`.
5. All other slots → `never_found`.
6. summary: met=0, unmet_with_ladder=7, …
7. stop_decision: continue (cycle 1).
