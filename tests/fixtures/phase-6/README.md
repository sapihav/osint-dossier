# Phase 6 v2 fixtures (R20)

Each fixture is a hand-replay test for the Phase 6 procedure in
`SKILL.md` against the catalog at `references/slots.md`. Fixtures
are referenced by acceptance criteria in
`references/phase-6-spec.md` §6.

## Structure

```
<fixture_name>/
  04-cross-ref.json         # input: simulated Phase 4 stage artifact
  expected-06-gaps.json     # expected output of the Phase 6 procedure
  notes.md                  # what this fixture asserts + replay walk-through
  [expected-render.md]      # expected Phase 7 snippet (only when relevant)
  [02-internal.gates.log]   # simulated Phase 2 state (only when relevant)
```

## Fixtures

| Fixture | Asserts |
|---|---|
| `s1_internal_only` | S1.1 non-substitution + S1.2 non-leak (criteria 2, 3) |
| `canonical_run` | L2 determinism + S3 mechanical satisfaction (criteria 5, 7) |
| `render_distinction` | Phase 7 affordance distinction (criterion 10) |
| `meta_v1_v2_mapping/contradictions` | v1→v2 mapping for `check_8` (criterion 12) |
| `meta_v1_v2_mapping/phase2` | v1→v2 mapping for `check_9` (criterion 12) |
| `worked_failure_trace` | The redesign's success proof (criterion 13) |

## How to replay

1. Read the fixture's `04-cross-ref.json`.
2. Walk the §5 procedure mentally: load catalog → filter
   `applies_when` → attach facts → compute eligibility → derive
   kind → build artifact.
3. Compare your output to `expected-06-gaps.json`. Any divergence
   is either a fixture bug, a catalog drift, or a procedure bug —
   reconcile in that order.
4. Record pass/fail in the PR body for the v0.5.0 (R20) PR.

These fixtures are NOT executed by CI. SKILL.md is prose, not
code; no test harness. Hand-replay is the regression net per spec
§1.5 / §6 residual risks.
