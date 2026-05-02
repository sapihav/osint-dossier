# meta_v1_v2_mapping/contradictions — v1 check_8 → v2 meta_check (criterion 12)

In v1, an unresolved contradiction set
`coverage.failed[].check_8_contradictions = true`. In v2, the same
state appears as `meta_checks.contradictions_resolved: false`.

## Key assertions

- `contradictions[]` non-empty → `meta_checks.contradictions_resolved == false`.
- "contradictions_resolved" does NOT appear in `escalation_eligible[]`
  (criterion 11 — meta-checks never escalate). R18 cannot fix
  Phase 4's contradiction count.
- The contradicting facts (fact_2, fact_3) still satisfy
  `current_role` from a count perspective — both pass grade and
  freshness. The contradiction is a separate, concurrent signal.
  Phase 7 will surface it via the audit footer, not via
  current_role.

## Why this is the right separation

If `check_8` had stayed a slot in v2, R18 would have read it as
escalation-eligible. But escalating to L4 cannot resolve a
contradiction — that's an operator decision (pick which source to
trust, or list both). The meta_checks split routes operator
attention correctly: contradiction → operator review, not more
spend.
