# canonical_run — L2 determinism + S3 mechanical satisfaction (criteria 5, 7)

A healthy mid-state run. Five slots met, two unmet with ladder.
Drives the L2 determinism assertion: replaying this fixture twice
must produce byte-identical `expected-06-gaps.json` modulo
`timestamp`.

## Per-slot derivation

| Slot | min_grade | min_sources | max_age | Eligible facts | Met | Kind |
|---|---|---|---|---|---|---|
| identity_confirmed | B | 1 | — | fact_1 (A) | ✓ | met |
| current_role | B | 2 | 365d | fact_2 (A, 2026-03-15), fact_3 (A, 2025-09-12) | ✓ | met |
| public_platforms | C | 2 | — | fact_4 (B), fact_5 (C) | ✓ | met |
| contact_method | C | 1 | — | fact_6 (C) | ✓ | met |
| career_history | B | 2 | — | fact_7 (A) | ✗ (count=1) | undersourced |
| current_location | C | 1 | 365d | fact_8 (C, 2026-03-15) | ✓ | met |
| photograph | D | 1 | — | (none attached) | ✗ | never_found |

`today` for the replay = `2026-05-02`. fact_3 (date 2025-09-12) is
within 365 days of today (2025-05-02 cutoff) — passes freshness.
fact_8 (date 2026-03-15) also passes 365d freshness.

## Escalation surface

Both unmet slots have non-empty `tier_ladder` and empty
`tiers_tried` → both in `escalation_eligible[]`. R18 will pick
each slot's first ladder entry next cycle.

## Meta-checks

`contradictions[]` is empty → `contradictions_resolved: true`.
Phase 2 was not attempted (no Phase-2 facts in input, no internal
gates log assumed) → `phase_2_attested: "skipped"`.

## Determinism check (replay protocol)

1. Run the procedure once. Capture output.
2. Run again with the same input. Capture output.
3. Diff the two outputs. Only `timestamp` may differ. Anything
   else is an L2 violation.
