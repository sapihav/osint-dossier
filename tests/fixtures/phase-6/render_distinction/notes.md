# render_distinction — Phase 7 affordance distinction (criterion 10)

Cycle 2 output where R18 has run between cycles. Tests the three
distinct render affordances in `assets/dossier-template.md`'s Gaps
block:

| Slot | tiers_tried | tier_ladder | Affordance |
|---|---|---|---|
| `current_role` | `[L1]` | `[L1, L3, L4]` | standard gap (try next un-tried) |
| `public_platforms` | `[]` | `[L1, L3]` | not yet attempted |
| `contact_method` | `[L1, L3]` | `[L1, L3]` | ladder exhausted |
| `career_history` | `[L1]` | `[L1, L3, L4]` | standard gap |
| `current_location` | `[]` | `[L1, L3]` | not yet attempted |
| `photograph` | `[]` | `[L1, L3]` | not yet attempted |

## Files

- `04-cross-ref.json` — input (1 fact, identity_confirmed met).
- `prior-cycle-06-gaps.json` — what cycle 1 produced AFTER R18
  appended to `tiers_tried` between cycles. Per the spec, this file
  is the post-R18-mutation state (R18's writes land in
  `06-gaps.json` directly per its own contract).
- `expected-06-gaps.json` — expected cycle 2 output. Carries
  `tiers_tried` forward verbatim from the prior file. Same
  `04-cross-ref.json` as cycle 1 ⇒ same met-status as cycle 1
  (escalation produced no new facts) ⇒ `summary.met` unchanged
  ⇒ plateau ⇒ `stop_decision: render-final`.
- `expected-render.md` — expected Phase 7 Gaps block.

## Key assertions

- `contact_method` is unmet AND `set(tiers_tried) == set(tier_ladder)`
  → it is NOT in `escalation_eligible[]` (R18 cannot escalate
  further), but it IS rendered in the Gaps block with the
  "ladder-exhausted" affordance.
- `summary.unmet_ladder_exhausted == 1`.
- Render block order = catalog order, with met slots omitted.
