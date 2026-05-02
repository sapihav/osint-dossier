# worked_failure_trace — the redesign's success proof (criterion 13)

This fixture replays the §1.2 scenario verbatim: subject "Jane Doe"
has only Phase 2 internal-promoted (Grade I) evidence of her current
role — no public source corroborates.

## What v1 did wrong

v1's `coverage[]` had `check_2_role` keyed on "any evidence found",
not "evidence of the right grade." Two Grade-I facts attached
to the role check satisfied it. R18 read `coverage.failed[]`,
didn't see `check_2_role` there, and didn't escalate. Phase 7
rendered "current role: Acme — Grade A" citing only
`[internal, operator-approved …]`. Silent double-counting, the very
pattern the four-gate protocol exists to prevent.

## What v2 must do

Slot `current_role` declares `internal_counts: false` (default).
Both facts have grade I. `passes_grade(f) ::=
(f.grade == "I" AND internal_counts == true) OR (f.grade ∈ {A,B,C,D} AND f.grade ≥ B)`.
Both fail. 0 eligible facts. `met = false`. Kind precedence: facts
attached (skip never_found), no fact passes grade → `low_grade`.

`current_role` lands in `escalation_eligible[]` because its
`tier_ladder: [L1, L3, L4]` is fully untried. R18 will pick L1 next
cycle.

## Non-leak check (S1.2)

The expected output's `current_role.where_and_how` is the catalog
template with safe variable substitution (`${name}`, `${handle}`).
The `evidence[]` array is `["fact_1", "fact_2"]` — fact_id
references only, never the claim text. The Grade-I content from
the input's `claim` field MUST NOT appear anywhere in the output.

## Replay walk-through

1. Load catalog (7 slots, all `applies_when: always`). 0 filtered.
2. Attach: only `current_role` has facts (fact_1, fact_2). All
   others have no facts.
3. Eligibility: fact_1 grade=I, internal_counts=false → fails
   passes_grade. Same for fact_2. 0 eligible per slot.
4. Kind: current_role → low_grade. All others → never_found.
5. Escalation: all 7 slots unmet, all have non-empty tier_ladder,
   all have empty tiers_tried → all 7 escalation-eligible.
6. Meta: contradictions empty → `contradictions_resolved: true`.
   Phase 2 ran and promoted (since fact_1 / fact_2 are Grade I and
   exist) → `phase_2_attested: "promoted"`.
7. summary: met=0, unmet_with_ladder=7, unmet_ladder_exhausted=0,
   applies_when_skipped=0. Invariants hold (0+7+0=7=len(slots);
   7+0=7=len(catalog)).
8. stop_decision: cycle=1, not all-met, not zero facts, not cycle
   3, not plateau (cycle=1) → `continue`.

`today` for the replay = `2026-05-02`. fact_1 date 2026-04-15 and
fact_2 date 2026-04-20 are both within `max_age_days: 365` —
freshness passes, but grade fails first per the precedence in
the procedure.
