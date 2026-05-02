# meta_v1_v2_mapping/phase2 — v1 check_9 → v2 meta_check (criterion 12)

In v1, an explicit "skip internal" Phase 2 decision set
`coverage.passed[].check_9_internal` (because skip-with-decision is
a valid attestation). In v2 the same state appears as
`meta_checks.phase_2_attested: "skipped"`.

## Spec name correction recorded at lock

Earlier spec drafts named this field `phase_5_attested` because the
text in §4.5 mistakenly tied "internal intelligence" to Phase 5.
The four-gate protocol is Phase 2, not Phase 5; the artifact path is
`stages/02-internal.gates.log`. Field renamed `phase_2_attested`
at lock 2026-05-02 — see spec §4.5 / §6 criterion 12.

## Files

- `04-cross-ref.json` — input (1 fact, no internal-promoted facts).
- `02-internal.gates.log` — simulated Phase 2 audit trail showing
  Gate 1 returned "skip internal." Phase 6 reads this to derive
  `phase_2_attested`.
- `expected-06-gaps.json` — expected output.

## Note: the gates-log format is invented for this fixture

Real Phase 2 writes to `stages/02-internal.gates.log` per R19, but
the log's actual line format is not formalized anywhere — R19 only
specified the path and that it carries gate-state, not the syntax.
The two-line `key=value` format here is illustrative; the real
parser used by Phase 6 v2 must accept whatever Phase 2 actually
emits. If a future PR formalizes the log syntax (and it should —
this is an R21 candidate per the parity audit), this fixture
should be updated to match, and Phase 6's "read the gates-log"
prose in `SKILL.md` should be tightened from "find the terminal
gate-state" to a specific parse rule.

## Key assertions

- Phase 6 reads `02-internal.gates.log` and finds a terminal
  gate-state of `skipped` → `meta_checks.phase_2_attested == "skipped"`.
- "phase_2_attested" does NOT appear in `escalation_eligible[]`
  (criterion 11). R18 cannot escalate to fix it — only the operator
  can re-run Phase 2 and choose differently.
- `phase_2_attested == "skipped"` is NOT a Phase 7 warning trigger
  (only `incomplete` is). The audit footer renders
  "internal-intelligence phase: skipped" plainly.
