---
title: "Phase 6 — Completeness & Gap Analysis Spec (R20)"
type: spec
status: in-progress
created: 2026-05-01
parent: ROADMAP.md#R20
---

> Working spec for the R20 redesign of Phase 6. Replaces the inline Phase 6
> prose in `SKILL.md` once locked. Goal: collapse three parallel data
> structures (`coverage[]`, `gaps[]`, `depth_score`) into a single shape,
> grounded in invariants — not in field-by-field migration. `/fsm-spec`
> drove the §2 invariant analysis (where "we missed a case" was the
> failure mode). §3–§6 use schema + procedure + acceptance criteria
> because the implementation surface (9 catalog rows, deterministic
> evaluation function, small artifact) doesn't have hidden states for
> formal FSM tables to surface — see §0 note.

## Status & Sequencing

- [x] §0 Triage — trigger properties named (combinatorial state; "we missed a case")
- [x] §1 Framing — locked 2026-05-01
- [x] §2 Invariants — locked 2026-05-01 (revised after self-review)
- [ ] §3 Slot catalog schema — drafted 2026-05-02
- [ ] §4 `06-gaps.json` v2 schema — drafted 2026-05-02
- [ ] §5 Phase 6 procedure — drafted 2026-05-02
- [ ] §6 Acceptance criteria — drafted 2026-05-02

§3–§6 await operator review/lock. Locks are revisable: if a later
section shows §2 missed an invariant, unlock §2 and revise — don't
work around it.

**Why §3–§6 are not formal FSM tables.** §0/§1 framed Phase 6 as
combinatorial-state — true for the *invariant question* (which is why
§2 stays formal). For the *implementation surface* (9 catalog rows, a
deterministic procedure, a small artifact) FSM-style dimensional
tables added ceremony without catching anything §2 didn't already
catch. Schema + procedure + acceptance-criteria is the right tool for
the §3–§6 question. The choice was reviewed and committed 2026-05-02.

---

## §1 — Framing

### 1.1 What Phase 6 is

Phase 6 sits between Phase 4 (graded fact list, `stages/04-cross-ref.json`)
and Phase 7 (render, `dossier.md` + `dossier.facts.jsonl`). Three external
consumers depend on its output (`stages/06-gaps.json`):

1. **Phase 7 render.** Fills the dossier's *Gaps* and *Coverage & Depth*
   sections.
2. **R18 escalation.** Decides whether to ascend a research tier
   (L1→L2→L3→L4). Reads the unmet-slot list; depth-only shortfalls do not
   justify L4 spend.
3. **Stopping criteria.** Decides `continue` / `render-with-note` /
   `render-final` for the next cycle.

### 1.2 Why redesign (R20 problem statement, condensed)

Today Phase 6 carries three parallel shapes describing the same world:

- `coverage[]` — 9 hardcoded binary checks with canonical IDs (v0.4.3).
- `gaps[]` — open-ended free-text "gap → where_and_how" rows.
- `depth_score` — weighted 7-dimension scalar, no link to coverage.

The relationship between the three is **not enforced anywhere**. R18 had
to bolt "eligibility = ID in `coverage.failed[]`" on top after the fact
(three commits to nail down semantics: v0.4.1 → v0.4.2 → v0.4.3);
`flips_check` keeps surfacing as a band-aid; five distinct gap kinds
(never-found, stale, low-grade, contradicted, undersourced) collapse into
one free-text string; agents have to interpret which gap-string maps to
which check.

**Worked failure trace (illustrative, not from a real run).** Subject has
internal-only ("Telegram DM") evidence of current employer. v1 marks
`check_2_role` as passed because *some* evidence exists. R18 reads
`coverage.failed[]`, doesn't see `check_2_role` there, doesn't escalate.
Phase 7 renders "current role: Acme — Grade A" citing only `[internal,
operator-approved …]`. The four-gate Phase 2 posture is violated by
silent double-counting — the very pattern the Grade-I tag was introduced
to prevent. v1 has no structural defence; the protection is a soft
instruction in SKILL.md prose.

This is exactly the "we missed a case" pattern. The redesign must make
the case *unrepresentable*, not just *discouraged*.

### 1.3 Working hypothesis & in-scope vs out-of-scope

The redesign's working hypothesis: replace `coverage[]` + `gaps[]` +
`depth_score` with a **slot catalog** (`references/slots.md`) + per-slot
status rows in `stages/06-gaps.json`. Coverage, depth, gaps, and R18
eligibility all derive from one shape.

**In scope for this spec:**

- The slot catalog's declarative shape (which fields each slot declares).
- Including the per-slot `tier_ladder` declaration that R18 reads.
- The `06-gaps.json` artifact shape (v2).
- The Phase 6 evaluation logic that turns `04-cross-ref.json` + catalog
  into a status row per slot.
- Stopping criteria.

**Out of scope:**

- Phase 4 grading rules (Grade A/B/C/D/I) — pre-existing, axiomatic input.
- Phase 2 four-gate protocol — pre-existing, axiomatic.
- R18's tier-selection mechanics ("read the slot's `tier_ladder`, pick
  the next un-tried entry") — that lives in R18, this spec only declares
  the catalog field R18 consumes.
- The dossier template (Phase 7 render) — bound by §6 acceptance criteria
  but not redesigned here.

This spec validates or refutes the slot hypothesis against invariants and
state-space enumeration. **Slots are not assumed; they earn the design
in §2's three-model comparison.**

### 1.4 Migration posture (per R20)

Either ship v1 (current, v0.4.3) or ship v2. **No field-by-field migration
across commits** — that is the path that produced R18 churn. The spec is
locked in full, then implementation is one PR.

### 1.5 Rollback plan

If v2 ships and a regression surfaces in production runs, the rollback is
**revert the v2 PR**, returning to v0.4.3. There is no in-place
downgrade path because v2 is a clean break (per §1.4). The pre-merge
gate is therefore the regression net: every §6 acceptance criterion must
have a passing test or an explicit "accepted residual risk" note before
merge. Post-merge, the first 3 dossier runs should be hand-audited
against expected slot states.

---

## §2 — Invariants  *(locked 2026-05-01, after self-review)*

A Phase 6 invariant is a rule that must hold for every produced
`stages/06-gaps.json`, regardless of subject, cycle, or escalation
history.

Tagged **axiom** (cannot be debated within R20 — derives from
project-level decisions in `DESIGN.md` or `ROADMAP.md`) vs **design**
(can be debated in this spec).

### Safety (forbidden states)

- **S1 — Grade-I non-substitution AND non-leak.**  *(axiom — DESIGN.md §2)*

  Two-part rule, one provenance:
  1. **Non-substitution.** An internal (Grade I) source never satisfies a
     check that requires public/external evidence. A slot whose only
     sources are Grade I is **unmet by construction**, regardless of how
     many internal sources exist.
  2. **Non-leak.** No field of `06-gaps.json` may embed content from
     Grade-I sources beyond the canonical
     `[internal, operator-approved YYYY-MM-DD]` cite. This includes
     `where_and_how`, slot status rows, gap descriptions, audit fields,
     and any free-text field — anywhere, ever.

  *Read vs quote.* Phase 6 may **count** Grade-I sources when computing
  met-status arithmetic (e.g., a slot that explicitly opts in via
  `internal_counts: true` may use them toward `min_sources`). It never
  **quotes** their content into any output field of `06-gaps.json`. The
  non-leak rule applies to *content embedding*, not to *use as a counted
  signal*. By default, slots have `internal_counts: false`, which is
  what makes the non-substitution rule structural.

  *Why:* the four-gate Phase 2 posture is the project's defining
  invariant. Without (1), "LinkedIn says X + internal chat says X ⇒
  Grade A" is silent double-counting. Without (2), the redacted-content
  guarantee leaks via a phase-6 prose field. Both rules share a single
  axiom — the four-gate protocol's mechanical promise that internal
  content never enters downstream artifacts.

- **S2 — Canonical IDs only.**  *(axiom — v0.4.3 lesson)*

  Every status row in `06-gaps.json` is keyed by a `slot_id` that exists
  in the slot catalog at the time of the run. No invented strings.
  Consumers (R18, Phase 7) match on `slot_id`, not on prose.

  *Why:* drift between phases produced the v0.4.2 → v0.4.3 churn. R18
  iterates the unmet-slot list; if IDs are not stable, R18 silently
  picks the wrong slot.

- **S3 — Mechanical satisfaction.**  *(design)*

  A slot's `met` status is computed mechanically from (a) the slot's
  declared targets in the catalog and (b) the candidate sources in
  `04-cross-ref.json`. No agent-set met flag; no prose-driven override.
  The set of declarable targets is fixed in §3 as a slot dimension —
  this invariant is about *who computes met*, not *which targets exist*.

  *Why:* without S3, Phase 6 becomes opinion. The whole grading apparatus
  (Phase 4) is wasted if Phase 6 can override. Mechanical computation
  is the precondition for L2 (determinism) and S4 (hard escalation
  predicate).

- **S4 — Hard escalation predicate.**  *(design — codifies R18 with no soft predicates)*

  R18's read surface (`escalation_eligible[]` in v2) contains exactly
  the slots whose status is `unmet` AND whose declared `tier_ladder`
  has at least one un-tried entry remaining. The predicate is
  mechanical — no "plausibly closable" runtime judgment. Slots with
  exhausted ladders are unmet but **not** escalation-eligible (they
  still render as gap hints to the operator, but R18 does not ascend
  on them). Depth-score shortfalls alone never produce entries.

  *Phase 7 rendering note.* Ladder-exhausted unmet slots and
  never-attempted unmet slots both fall outside `escalation_eligible[]`,
  but Phase 7 must render them with distinct affordances — "tried
  L1+L3, no result" vs "not yet attempted" carries operationally
  distinct information for the operator (one signals "spend more here
  is probably wasted", the other signals "spend more here is the
  obvious next move"). The status row therefore carries `tiers_tried[]`
  alongside `tier_ladder`, and Phase 7 picks the rendering accordingly.
  Concrete render rules are a §6 acceptance criterion seed.

  *Why:* "plausibly closable" was a soft predicate that breaks L2
  determinism. Per-slot `tier_ladder` is declarative — operators
  encode "Phase 6 should try L1 first, then L3" once, in the catalog,
  reviewable in PR. L4 ($0.50–$5/call, ≥ project budget cap) is a
  footgun without a hard predicate.

### Liveness (must eventually hold)

- **L1 — Bounded termination.**  *(axiom — cycle cap preserved from v1; plateau definition revised 2026-05-02 by Q1 resolution)*

  Phase 6 terminates within ≤3 cycles, OR on plateau
  (`summary.met` did not increase since the prior cycle), OR on
  all-met. Whichever fires first. Within a single cycle, evaluation
  is a finite pass over the catalog. Count-based plateau is
  intentionally permissive of a met→unmet regression (which can
  happen if Phase 4 regrades a fact downward across cycles): if
  coverage is going sideways or backwards, continuing won't help.

  *Plateau revision history.* v1 defined plateau as `depth_score Δ <
  0.5`. Q1 (resolved 2026-05-02 in §5.4) eliminates `depth_score`;
  plateau is therefore redefined as "no new slot met." Operationally
  equivalent for the runaway-spend hazard: both fire when escalation
  isn't producing meet-state progress.

  *Why:* without L1 the escalation loop is unbounded; combined with L4
  costs ($0.50–$5/call), that is a runaway-spend hazard.

- **L2 — Render-determinism.**  *(design)*

  Two Phase 6 runs over the same `04-cross-ref.json`, same slot catalog,
  same cycle index, and same `applies_when` evaluation context (i.e.,
  same set of "did Phase N run?" booleans) produce the same
  `06-gaps.json` modulo timestamp and ts-derived fields. Order of slot
  rows is catalog declaration order, **modulo slots filtered out by
  `applies_when`** (e.g., phase-5-only slots are absent when Phase 5
  did not run; surviving slots stay in their original relative order).
  No model-dependent prose in any load-bearing field — `where_and_how`
  is a catalog-declared template with deterministic variable
  substitution from Phase 4 facts, not free-form generation.

  *Why:* R19 stage-resumability is the explicit motive — Phase 7 must be
  re-runnable from `06-gaps.json` without re-running Phase 6. Free-form
  agent prose in load-bearing fields breaks this.

### Operational

- **O1 — Catalog as authority.**  *(design — the redesign's premise)*

  The slot catalog (`references/slots.md`) is the single source of truth
  for **what** Phase 6 evaluates. Phase 6 reads the catalog at runtime;
  adding/changing/removing a slot is a catalog edit. Phase 6 prose in
  `SKILL.md` does not enumerate checks.

  *Falsifiable test:* a hypothetical PR that adds a check by editing
  `SKILL.md` only — without touching the catalog — must be rejected.
  Conversely, adding a slot row to `references/slots.md` must produce a
  new entry in `06-gaps.json` with no SKILL.md change.

  *Why:* this is *the* invariant the redesign is for. Without O1, slots
  are just a different way to spell `coverage[]` and we get R18 churn
  again.

- **O2 — Schema-version handshake.**  *(design)*

  Every `06-gaps.json` carries `schema_version: "2"` at the top level.
  **Producers** (the Phase 6 procedure in `SKILL.md`) MUST set the
  field. **Consumers** (the R18 escalation procedure, the Phase 7
  render procedure, any downstream tooling) MUST verify
  `schema_version == "2"` as the **first** read on the artifact; on
  absence or mismatch they MUST stop and surface the version skew —
  never read further fields, never synthesize defaults.

  *Operationalization in a prose-driven skill.* Because R18 and Phase 7
  are SKILL.md procedure prose, not code, the handshake is enforced as
  an explicit instruction at the top of each consumer block:
  *"Read `schema_version` from `stages/06-gaps.json`. If absent or not
  `"2"`, stop with an error: 'Phase 6 artifact schema mismatch — see
  references/phase-6-spec.md §2 O2'. Do not proceed."* This is the
  full enforcement surface — there is no separate runtime guard. The
  tradeoff is accepted: a human reviewing a SKILL.md edit that touches
  the artifact shape must check both producer and consumer prose
  together.

  *Why:* R20 mandates a v1→v2 bump and forbids field-by-field migration
  (§1.4). Without O2, deploying the v2 producer alongside an unaware
  v1 consumer (R18 today, hypothetical future tooling tomorrow) =
  silent breakage. The handshake makes the breakage loud at the first
  read of the artifact.

### Decided open questions

- **~~Q1~~ → Decided 2026-05-02 (§5.4).** `depth_score` is **eliminated**.
  Plateau detection moves to "no new slot met since prior cycle"
  (`summary.met` Δ). Phase 7's depth surface becomes met-count + per-grade
  distribution, both derivable from `slots[]` + `evidence[]`. Accepted
  residual risk: grade-improving churn that doesn't cross `min_grade`
  triggers plateau — designed behavior, not a regression.
- **~~Q2~~ → Decided.** `max_age_days` is **optionally** declared per
  slot in the catalog. A slot that does not declare it is not gated on
  freshness. Becomes a §3 slot-type dimension.
- **~~Q3~~ → Decided.** Single catalog file. Phase-5-only slots carry an
  `applies_when: phase_5_run` flag and are skipped in
  `06-gaps.json` when Phase 5 didn't run (not even as `unmet`). Keeps
  catalog discoverability and avoids file-split overhead.
- **~~Q4~~ → Decided.** Per-slot `tier_ladder` is a catalog field. R18
  reads it; this spec declares the field's existence and shape only —
  R18's selection logic ("pick next un-tried entry") is out of scope
  per §1.3. Folded into S4 as the hard predicate.

### Three-model comparison against §2

The "best option" claim requires cross-walking *all three* candidate
models against §2, not just slots. For each invariant, the table below
shows where each model strains (i.e., what design-level gymnastics the
model has to do to satisfy the invariant).

| Inv | Slot model | Tagged-fact model | Rule-engine model |
|---|---|---|---|
| **S1** non-sub+non-leak | per-slot `internal_counts: false` default; `where_and_how` is template + safe vars only | per-tag flag + post-aggregation re-filter; leak risk in tag descriptions | per-rule predicate must exclude Grade-I and predicate body must be lint-clean of internal content — runtime burden |
| **S2** canonical IDs | catalog IS the registry | tags are de-facto registry but tag-set lives across facts (mutability harder) | predicates have IDs; rule-set drift is a real risk |
| **S3** mechanical sat. | declarative target fields → arithmetic on Phase 4 facts | needs aggregator step to count tag matches; aggregator becomes second logic layer | predicate evaluator IS the mechanical layer (clean) but predicate language is unbounded |
| **S4** hard escalation | `tier_ladder` per slot, declarative | needs `tier_ladder` per tag-class — same shape, different home | needs `tier_ladder` per predicate ID; AST-walk to decide eligibility |
| **L1** termination | orthogonal to model | orthogonal | orthogonal |
| **L2** determinism | catalog-static `where_and_how` template + Phase 4 → mechanical render | per-tag aggregation order must be specified; risk of agent-driven gap synthesis | predicate evaluator must be deterministic (achievable but auditing burden grows with predicate language) |
| **O1** catalog auth. | by construction (slot rows ARE the catalog) | tags-as-catalog works but tags live on facts, so "edit catalog → fact rows update" is a join, not an edit | predicates ARE the catalog (works) but predicate language maintenance is non-trivial |
| **O2** schema handshake | trivial top-level field | trivial | trivial |

**Where each model strains hardest:**

- **Slot model** — strains nowhere catastrophically. The hardest cell
  (L2 / `where_and_how`) is resolved by catalog-declared templates
  (decided in this spec).
- **Tagged-fact model** — strains S3 and L2. Aggregation step adds a
  second logic layer between facts and slot-rows; agent-driven
  aggregation risks L2 violation. Strain is fixable but requires the
  same per-tag declarative target shape that slots use — at which
  point the model collapses into the slot model with a different
  output shape (per-fact rows vs per-slot rows). Phase 7 needs
  per-slot output (Coverage section is per-check); R18 needs per-slot
  output (escalation is per-check). **Per-fact output requires
  aggregation regardless** — slot model just bakes the aggregation in.
- **Rule-engine model** — strains S2, L2, and O1 simultaneously.
  Predicate language becomes a mini-DSL to maintain. Reviewable diffs
  on the catalog become harder. For ~10 checks, the language overhead
  outweighs the flexibility.

**Conclusion.** Slot model wins on §2-strain analysis: zero hard
strains, declarative target shape that R18 can consume directly, and
the per-slot output matches both Phase 7 and R18 consumer surfaces.
Tagged-fact would re-converge to slots after fixing its strain
points; rule-engine adds a maintained mini-language with no commensurate
benefit at this scale. **Locked.** If §3-§5 surface a flaw, the
documented fork-points are the alternatives.

---

## §3 — Slot catalog schema (`references/slots.md`)

The catalog is the authority per O1: one row per check, declared
fields parameterize Phase 6's evaluation. Adding a row produces a new
entry in `06-gaps.json` with no SKILL.md change.

### 3.1 Fields per slot row

| Field | Type | Required? | Purpose |
|---|---|---|---|
| `slot_id` | string (snake_case, stable) | yes | Canonical ID per S2. Consumers (R18, Phase 7) match on this. Once published, never renamed without a v→v+1 catalog migration. |
| `description` | string (one line) | yes | Human-readable label for catalog review and Phase 7 render. |
| `min_grade` | enum `A`/`B`/`C`/`D` | yes | Lowest acceptable Phase 4 grade among A/B/C/D. Facts below this don't count toward `met`. (Grade I is governed by `internal_counts`, not by `min_grade`.) |
| `min_sources` | int ≥ 1 | yes | Minimum count of eligible facts (after grade/freshness/internal filters) for `met`. Default 1; ≥ 2 for high-stakes slots like current employer. |
| `tier_ladder` | ordered non-empty list of `L1`/`L2`/`L3`/`L4` | yes | R18 reads this. Order = priority. R18 picks first un-tried entry. Must contain at least one tier — a slot with no escalation path should not be in the catalog. |
| `where_and_how_template` | string with `${var}` placeholders | yes | Phase 7 renders this for unmet slots. Variables substitute deterministically from Phase 4 facts (per L2). No free-form generation. |
| `applies_when` | enum `always`/`phase_5_run` | no, default `always` | Per Q3 lock, slot is filtered out of `06-gaps.json` entirely when condition is false. |
| `max_age_days` | int > 0 | no, default unset | If set, facts older than this don't count toward `met`. If unset, no freshness gate. |
| `internal_counts` | bool | no, default `false` | Per S1.1 default: `true` only when slot explicitly opts in to count Grade-I sources toward `min_sources`. The default of `false` is what makes non-substitution structural. |

### 3.2 Fields explicitly NOT in the row

- **No `weight`.** That was a `depth_score` artifact (eliminated per Q1; see §5.4).
- **No `kind`.** Kind is derived per fact-set (see §5.1 step 4), not declared.
- **No per-kind gap-string templates.** Catalog row owns one
  `where_and_how_template` (the catalog-stable affordance). Phase 7
  composes the kind-label and the affordance at render time.
- **No meta-attestation checks.** v1's `check_8_contradictions` and
  `check_9_internal` are NOT slots — they don't fit the
  `min_grade`/`min_sources` shape because they ask "was the *process*
  followed?" not "was the *data* found?". They live as top-level
  `meta_checks{}` in `06-gaps.json` (§4.5). v1 force-fit them into
  `coverage[]` because there was nowhere else; v2 categorizes
  correctly. The redesign's "single shape" goal applies to coverage
  proper (slot rows replace `coverage[]` + `gaps[]` + `depth_score`);
  attestation is a structurally different concern.

### 3.3 Catalog file format

Markdown with a YAML frontmatter codeblock per slot, OR a single
YAML/TOML file. Decided at implementation time; the spec only
requires that the file be readable as a list of typed rows matching
§3.1. Variable surface for `where_and_how_template` is documented in
the catalog file header and frozen for the v2 schema lifetime
(adding a variable is a v3 schema bump).

### 3.4 Worked example

```yaml
- slot_id: current_employer
  description: Subject's current employer (organization name + role)
  min_grade: B
  min_sources: 2
  tier_ladder: [L1, L3]
  where_and_how_template: "Look on LinkedIn (/in/${handle}); cross-check via company press release or filings"
  max_age_days: 365
  # internal_counts omitted → defaults to false
  # applies_when omitted → defaults to "always"
```

The omission of `internal_counts` here is the structural defence to
the §1.2 worked failure trace: Telegram-DM-only evidence cannot
satisfy this slot.

---

## §4 — `06-gaps.json` v2 schema

Single artifact emitted per Phase 6 cycle, consumed by R18 and Phase 7.

### 4.1 Top-level shape

```json
{
  "schema_version": "2",
  "cycle": 1,
  "slots": [SlotStatusRow, ...],
  "escalation_eligible": ["slot_id_a", "slot_id_b"],
  "meta_checks": {
    "contradictions_resolved": true,
    "phase_5_attested": "skipped"
  },
  "summary": {
    "met": 5,
    "unmet_with_ladder": 3,
    "unmet_ladder_exhausted": 1,
    "applies_when_skipped": 2
  },
  "stop_decision": "continue",
  "timestamp": "2026-05-02T12:00:00Z"
}
```

| Field | Notes |
|---|---|
| `schema_version` | REQUIRED. MUST be the first key. Per O2, consumers read this first; absence or `!= "2"` ⇒ stop with the §2-O2 error. |
| `cycle` | 1, 2, or 3 (per L1 cap). |
| `slots` | Ordered list (§4.3). |
| `escalation_eligible` | R18's read surface (§4.4). Meta-checks are NOT escalatable — they never appear here. |
| `meta_checks` | Process attestations (§4.5). |
| `summary` | Roll-up for stopping logic (§5.2) and Phase 7 render header. Two invariants hold: (a) `met + unmet_with_ladder + unmet_ladder_exhausted == len(slots)`; (b) `len(slots) + applies_when_skipped == len(catalog)`. |
| `stop_decision` | `continue` / `render-with-note` / `render-final`. Set by Phase 6 (§5.2). |
| `timestamp` | The only field allowed to differ between two replays of the same input (per L2). |

### 4.2 SlotStatusRow

```json
{
  "slot_id": "current_employer",
  "met": false,
  "kind": "undersourced",
  "where_and_how": "Look on LinkedIn (/in/jdoe); cross-check via company press release or filings",
  "tiers_tried": ["L1"],
  "evidence": ["fact_42", "fact_57"]
}
```

| Field | Type | Notes |
|---|---|---|
| `slot_id` | string | Matches a row in `references/slots.md` (per S2). |
| `met` | bool | Mechanically computed per S3 / §5.1 step 3. |
| `kind` | enum `met` / `never_found` / `low_grade` / `undersourced` / `stale` | Derived per §5.1 step 4. Equals `met` when `met == true`; otherwise one of the four unmet kinds. |
| `where_and_how` | string | Catalog template with deterministic variable substitution. May be empty when `met == true`. |
| `tiers_tried` | ordered list of `L1`/`L2`/`L3`/`L4` | Populated by R18 between cycles, preserved by Phase 6 across cycles (§5.1 step 5). Empty on cycle 1 before R18 has run. |
| `evidence` | list of Phase 4 fact_ids | Empty when `kind == "never_found"`. |

### 4.3 Row order (per L2 + Q3)

Catalog declaration order, with `applies_when=false` slots filtered
out. Surviving slots stay in their original relative order. Two runs
over the same catalog and same `applies_when` context produce the
same order.

### 4.4 `escalation_eligible[]` (per S4)

Top-level (not nested in slot rows) so R18 reads one field.

```
escalation_eligible = [ row.slot_id
                        for row in slots
                        if row.met == false
                        and (catalog[row.slot_id].tier_ladder \ row.tiers_tried) ≠ ∅ ]
```

Slots whose `tier_ladder` is fully exhausted are unmet but not
eligible — they still render via Phase 7 with the "tried L1+L3, no
result" affordance per the §2 S4 render note.

### 4.5 `meta_checks{}` (process attestations)

These are NOT slots and NOT in `escalation_eligible[]` — escalation
cannot fix them. They are read by Phase 7 for the dossier's
attestation footer.

| Field | Type | Source | Render meaning |
|---|---|---|---|
| `contradictions_resolved` | bool | True iff `04-cross-ref.json` reports zero unresolved contradictions. (Phase 4 owns the count; Phase 6 reads it. Out of scope: how Phase 4 detects contradictions.) | False ⇒ dossier renders "⚠ N unresolved contradictions in source set" footer. |
| `phase_5_attested` | enum `promoted` / `skipped` / `incomplete` | Determined from Phase 5's audit signal (presence of `stages/05-internal.json` AND its terminal status). `skipped` is a valid attestation per the four-gate protocol — the operator made a decision. `incomplete` ⇒ Phase 5 started but didn't reach a terminal state. | `incomplete` is the only value that triggers a Phase 7 warning. `promoted` and `skipped` both render as "internal-intelligence phase: <attestation>" in the audit footer. |

**Maps to v1.** `contradictions_resolved` replaces `check_8_contradictions`;
`phase_5_attested` replaces `check_9_internal`. v1 surfaced both as
binary `coverage[]` entries — that mis-modelled them as data-found
checks. v2 separates concerns: `slots[]` is data coverage,
`meta_checks{}` is process attestation.

### 4.6 No `depth_score`

Q1 resolved in favor of elimination. See §5.4.

---

## §5 — Phase 6 procedure

Phase 6 is a deterministic function:
`(04-cross-ref.json, references/slots.md, prior-cycle 06-gaps.json if any) → new 06-gaps.json`.
Five steps.

### 5.1 Steps

1. **Load catalog and filter by `applies_when`.** Read
   `references/slots.md`. For each row, evaluate `applies_when`
   against the run context (booleans for "did Phase N run"). Drop
   rows that evaluate false. Surviving rows in declaration order =
   the slot list for this cycle. Filtered-out count goes into
   `summary.applies_when_skipped`.

2. **Attach Phase 4 facts to slots.** Read `04-cross-ref.json`. For
   each surviving slot, collect facts that map to its `slot_id`.
   (Mapping convention: each Phase 4 fact carries a `slot_id` field
   assigned during Phase 3. Pre-existing convention, out of scope.)

3. **Compute eligibility per fact, then `met` per slot.** Define
   (grade ordering: `A > B > C > D`; `I` is a separate axis governed
   by `internal_counts`, not ordered against A/B/C/D):
   - `passes_grade(f) ::= (f.grade ∈ {A,B,C,D} AND f.grade ≥ min_grade) OR (f.grade == "I" AND internal_counts == true)`
   - `passes_freshness(f) ::= max_age_days unset OR f.date ≥ today - max_age_days`
   - `eligible(f) ::= passes_grade(f) AND passes_freshness(f)`
   - `met ::= count(eligible facts) ≥ min_sources`

4. **Derive `kind`.** For `met` slots, `kind = "met"`. For unmet
   slots, walk the precedence top-down (first match wins):

   | Order | Kind | Condition |
   |---|---|---|
   | 1 | `never_found` | `facts_attached == ∅` |
   | 2 | `low_grade` | no fact `passes_grade` (covers Grade-I-only with `internal_counts: false`; covers all-D when `min_grade == B`; etc.) |
   | 3 | `stale` | `max_age_days` declared AND ≥1 fact `passes_grade` AND no fact `passes_grade ∧ passes_freshness` |
   | 4 | `undersourced` | otherwise (≥1 eligible fact but `count < min_sources`) |

   Rationale for `low_grade` covering the Grade-I-only case: from the
   operator's vantage, "the evidence we have is too weak by our
   declared rules" is the actionable signal. `where_and_how` (the
   catalog template) carries the *what to do next* — "look on
   LinkedIn", "cross-check via filings" — which already directs the
   operator to external sources. Adding a 5th kind would not change
   the operator's next move.

5. **Build the artifact.**
   - For each slot, render `where_and_how` from
     `where_and_how_template` with deterministic variable
     substitution from Phase 4 facts. No free-form generation.
   - Carry forward `tiers_tried` from prior cycle's row of the same
     `slot_id`. (Cycle 1: empty list.) Catalog edits between cycles
     are unsupported; if a `slot_id` exists in this cycle but not
     prior, treat as cycle 1 for that slot.
   - Compute `escalation_eligible` per §4.4.
   - Compute `meta_checks{}` per §4.5: read Phase 4's contradiction
     count for `contradictions_resolved`; read Phase 5's audit
     signal for `phase_5_attested`.
   - Compute `summary` counts.
   - Compute `stop_decision` per §5.2.
   - Emit `06-gaps.json` with `schema_version: "2"` as the first key.

   **Contract with R18 on `tiers_tried`.** When R18 escalates a slot
   between cycles, it appends the tier it ran to that slot's
   `tiers_tried` in the current `06-gaps.json` — and only if that
   tier is not already present (effective semantics is a set;
   serialized as an ordered list to preserve attempt order for
   Phase 7 render). Phase 6's "carry forward" in step 5 then reads
   the post-R18 state. This makes `06-gaps.json` the single source
   of truth for slot status across cycles (no separate R18 audit log
   to reconcile). R18's append logic itself is out of scope per
   §1.3, but the contract that R18 writes here is on this spec's
   surface.

### 5.2 Stopping criteria (resolves L1)

Evaluated in order; first match wins:

1. `04-cross-ref.json` had zero facts → `render-with-note`
   (degenerate, see §5.3).
2. All slots `met == true` → `render-final`.
3. `cycle == 3` → `render-final` (cycle cap).
4. `cycle > 1` AND `summary.met` did not increase since prior
   cycle → `render-final` (plateau).
5. Otherwise → `continue`.

### 5.3 Edge case: zero Phase-4 facts

If `04-cross-ref.json` contains zero facts (Phase 4 produced
nothing), every surviving slot is emitted as
`{met: false, kind: "never_found", evidence: [], tiers_tried: []}`.
`escalation_eligible` is populated as normal (every slot with
non-empty `tier_ladder` is eligible, since `tiers_tried == []`).
`stop_decision` is `render-with-note`, signaling Phase 7 to render
a "no Phase 4 evidence" warning header. R18 may still escalate from
this state on cycle 1.

### 5.4 Q1 resolved — `depth_score` is eliminated

Plateau detection used `depth_score` Δ in v1. With slots, plateau is
detected by `summary.met` unchanged from prior cycle — a cleaner
signal in the slot world (no new check passed = no progress).
Phase 7's "Coverage & Depth" section becomes met-count + per-grade
distribution across met slots (`{A: 2, B: 1, C: 0}`), both derivable
from `slots[]` + their `evidence` arrays.

**Loss of v1 signal.** A slot going from "10 D-grades" to "10 B-grades"
without crossing `min_grade` doesn't change `met` and triggers
plateau. **Accepted residual risk:** such churn IS plateau by design.
Escalation that produces lower-tier evidence without changing the
met-set is cycle waste; cutting cycle 3 short here is correct
behavior, not a regression.

---

## §6 — Acceptance criteria

These are the rollback gate per §1.5. Each criterion has a test
strategy. Where automated tests aren't feasible (SKILL.md is prose,
not code), the strategy is **manual replay** against
`tests/fixtures/phase-6/<name>.json`. The first 3 production dossier
runs after merge are hand-audited per §1.5.

**Fixtures are part of the v2 PR scope.** All fixture files
referenced below are created by the v2 PR; none exist pre-merge.
Per §1.4 ("one PR"), the PR is not mergeable without them.

### Schema & invariants

1. **(O2) Schema handshake.** Both R18 and Phase 7 prose blocks
   in `SKILL.md` contain the explicit instruction from §2-O2 as the
   first read on `06-gaps.json`. *Test:* code-search SKILL.md for
   the exact `'Phase 6 artifact schema mismatch — see references/phase-6-spec.md §2 O2'`
   instruction text in both consumer blocks.

2. **(S1.1) Non-substitution.** A slot with `internal_counts: false`
   (default) and Phase 4 facts that are exclusively Grade-I emits
   `met: false, kind: "low_grade"` regardless of fact count.
   *Test:* fixture `s1_internal_only.json` replays to expected output.

3. **(S1.2) Non-leak.** No string field anywhere in `06-gaps.json`
   contains text from a Grade-I source. *Test:* fixture run with
   Grade-I evidence; assert that the only Grade-I appearance is the
   canonical `[internal, operator-approved YYYY-MM-DD]` cite as a
   `fact_id` reference inside `evidence[]`, never as quoted content
   in any prose field.

4. **(S2) Canonical IDs.** Every `slot_id` in `06-gaps.json`
   exists in `references/slots.md` for the same run.
   *Test:* JSON-vs-catalog membership check on every run output.

5. **(S3) Mechanical satisfaction.** Two Phase 6 runs over identical
   `04-cross-ref.json` + identical catalog produce identical `met`
   for every slot. *Test:* subset of #7.

6. **(S4) Hard escalation predicate.** `escalation_eligible[]`
   exactly equals
   `{row.slot_id : row.met == false AND tier_ladder \ tiers_tried ≠ ∅}`.
   *Test:* fixture replay, set-equality assertion. Sub-test: a slot
   that is `met` exactly at `min_grade` (e.g., only C-grade facts
   when `min_grade == C`) does NOT appear in `escalation_eligible` —
   depth-only shortfalls produce no entries even when the operator
   might wish for higher-grade evidence.

7. **(L2) Determinism.** Two runs over identical inputs produce
   identical `06-gaps.json` modulo `timestamp`. *Test:* replay+diff
   on `tests/fixtures/phase-6/canonical_run.json`.

8. **(L1) Termination.** No fixture run exceeds 3 cycles. *Test:*
   instrumented run over fixtures asserts `cycle ≤ 3` at termination.

9. **(O1) Catalog authority.** Two checks:
   - *Diff-only PR test:* a PR that adds a row to
     `references/slots.md` (no SKILL.md edit) produces a new entry
     in `06-gaps.json` for the next run. Manual replay.
   - *Static check:* `grep -rE "<slot_id_literal>" SKILL.md` finds
     no slot_id strings — SKILL.md must not enumerate them.

### Consumer surface

10. **Phase 7 render distinction (per S4 render note).**
    Ladder-exhausted unmet slots (`set(tiers_tried) == set(tier_ladder)`)
    and never-attempted unmet slots (`tiers_tried == []`) render with
    distinct affordances in `dossier.md`. *Test:* snapshot comparison
    against fixture render in `tests/fixtures/phase-6/render_distinction/`.

### Meta-checks (process attestation, §4.5)

11. **Meta-checks never escalate.** For any fixture run,
    `meta_checks{}` is populated AND no key from `meta_checks{}`
    appears in `escalation_eligible[]`. *Test:* set-disjointness
    assertion on every fixture. Rationale: escalation cannot fix
    Phase 4's contradiction count or Phase 5's audit status; surfacing
    them as escalatable would mis-route operator attention.

12. **v1 → v2 attestation mapping.** A fixture that replays v1's
    `check_8_contradictions == false` (i.e., Phase 4 reports ≥1
    unresolved contradiction) emits `meta_checks.contradictions_resolved == false`
    in v2. A fixture that replays v1's `check_9_internal == "skipped"`
    emits `meta_checks.phase_5_attested == "skipped"`.
    *Test:* paired fixtures `meta_v1_v2_mapping/{contradictions,phase5}.json`.

### Closure

13. **Worked failure trace closure (§1.2).** The exact "Telegram-DM-only
    confirms current role" scenario from §1.2 emits
    `{slot_id: "current_employer", met: false, kind: "low_grade"}`
    under v2 with `current_employer.internal_counts == false`
    (default). *Test:* fixture `worked_failure_trace.json` replays
    to that output. **This is the proof of redesign success** — v1
    silently passed this case; v2 must structurally fail it.

### Accepted residual risks

- **No automated S1.2 (non-leak) regex.** Grade-I content can be
  arbitrary natural-language text; no regex catches all cases.
  *Mitigation:* hand-audit of fixture `s1_internal_only.json` is a
  REQUIRED step on every PR that touches `06-gaps.json` shape or
  Phase 6 procedure. Recorded in PR body.
- **Manual replay rather than automated CI.** SKILL.md is prose;
  there is no test harness. *Mitigation:* fixture replay is run by
  the PR author and recorded in PR body. The first 3 production
  dossier runs after merge are hand-audited per §1.5.
- **Plateau false positives on grade-improving churn (§5.4).**
  Accepted as design behavior — see §5.4 rationale.

---

## References

- `ROADMAP.md` §R20 — redesign rationale
- `ROADMAP.md` §R18 — research-escalation cost tiers (escalation consumer)
- `ROADMAP.md` §R19 — stage-by-stage artifact persistence (resumability
  consumer)
- `DESIGN.md` §2 — four-gate Phase 2 protocol; Grade-I rationale
- `SKILL.md` "Phase 6 — Completeness & Gap Analysis" — current v1 logic
- `assets/dossier-template.md` — Phase 7 consumer surface
