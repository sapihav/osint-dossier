---
title: "Phase 6 — Slot catalog"
type: catalog
schema_version: 2
parent: references/phase-6-spec.md
---

# Phase 6 slot catalog

Authoritative declaration of the checks Phase 6 evaluates per
`references/phase-6-spec.md` §3 (locked 2026-05-02). One row per
slot. Adding/removing a row is a catalog edit; SKILL.md does NOT
enumerate slot IDs (per O1).

**Consumers:**

- Phase 6 procedure (loads, filters by `applies_when`, evaluates).
- R18 escalation (reads `tier_ladder` per slot via the in-cycle
  `06-gaps.json[].slots[]` rows).
- Phase 7 render (uses `description` + `where_and_how_template`).

## Variable surface for `where_and_how_template`

Frozen for the v2 schema lifetime per spec §3.3. Adding a variable
is a v3 schema bump.

| Variable | Resolves to | Source | Fallback if unresolved |
|---|---|---|---|
| `${name}` | Subject's full name as supplied at Phase 0. | `stages/00-tooling.json[].subject_name` | Empty string. |
| `${handle}` | Best-available platform handle (LinkedIn first, then Twitter/X, then Instagram). | First non-empty handle in declaration order across `stages/03-platform-*.json[].rows[].handle`. | Empty string. |
| `${slug}` | Dossier slug. | `stages/00-tooling.json[].slug` | Empty string (never empty in practice; Phase 0 enforces). |

Substitution is literal. No conditional logic, no default
expressions, no escaping needed (templates render into markdown
prose, not into URLs or JSON).

## Slots

```yaml
slots:
  - slot_id: identity_confirmed
    description: Subject correctly identified — not a namesake collision.
    min_grade: B
    min_sources: 1
    tier_ladder: [L1, L4]
    where_and_how_template: "Cross-check ${name} against a second public source (official bio, employer site, verified profile) — name-collision risk if only one match."
    # internal_counts omitted → false (S1.1 non-substitution: identity must be public-grounded)

  - slot_id: current_role
    description: Subject's current role and organisation.
    min_grade: B
    min_sources: 2
    tier_ladder: [L1, L3, L4]
    where_and_how_template: "Look on LinkedIn (/in/${handle}); cross-check via company press release, filings, or official site."
    max_age_days: 365
    # internal_counts omitted → false (Telegram-DM-only confirmation does NOT satisfy)

  - slot_id: public_platforms
    description: At least 2 public platforms with a profile (proof of digital footprint).
    min_grade: C
    min_sources: 2
    tier_ladder: [L1, L3]
    where_and_how_template: "Search ${name} across LinkedIn, Twitter/X, Instagram, GitHub, personal site — surface ≥2 distinct profiles."

  - slot_id: contact_method
    description: At least one public contact method (email, public DM handle, official form).
    min_grade: C
    min_sources: 1
    tier_ladder: [L1, L3]
    where_and_how_template: "Look at ${name}'s personal site, GitHub profile bio, conference speaker page, or company contact directory."

  - slot_id: career_history
    description: Career history — 2+ verifiable past or current positions.
    min_grade: B
    min_sources: 2
    tier_ladder: [L1, L3, L4]
    where_and_how_template: "Walk LinkedIn (/in/${handle}) experience section; cross-check at least one prior position via press release, GitHub org membership, or conference bio."

  - slot_id: current_location
    description: Subject's current city/region.
    min_grade: C
    min_sources: 1
    tier_ladder: [L1, L3]
    where_and_how_template: "Check LinkedIn location field; corroborate via Twitter/X bio, conference attendance, or geotagged content."
    max_age_days: 365

  - slot_id: photograph
    description: At least one photograph of the subject.
    min_grade: D
    min_sources: 1
    tier_ladder: [L1, L3]
    where_and_how_template: "Pull profile picture from LinkedIn (/in/${handle}), conference speaker page, company team page, or news photo."
```

## Untested escape-hatch fields (review burden for first adopter)

Two fields declared in spec §3.1 are present in the schema but
exercised by **zero** v2 catalog rows:

- `applies_when` — defaults to `always`. Drop a slot from
  `06-gaps.json` based on a run-context boolean (only
  `phase_5_run` is defined today). The `summary.applies_when_skipped`
  count exists for this. v2 has no Phase-5-only slot.
- `internal_counts` — defaults to `false`. The structural defence
  for spec invariant S1.1 (non-substitution): a slot with this
  set to `true` would count Grade-I facts toward `min_sources`.
  The default of `false` is what makes Grade-I-only evidence
  unable to satisfy any v2 slot.

**The first PR that exercises either field MUST also extend
`tests/fixtures/phase-6/` with a fixture that asserts the new
behaviour.** Reasoning: untested surface tends to drift; both
fields are load-bearing IF used (the `internal_counts` default
of `false` IS what enforces non-substitution mechanically), so
the first opt-in needs explicit fixture coverage.

For `internal_counts: true` specifically, also re-verify the
S1.2 non-leak invariant by hand — Grade-I content getting into
prose fields is the failure mode that motivated the four-gate
protocol in the first place.

## v1 → v2 mapping

| v1 `coverage[]` ID | v2 destination | Notes |
|---|---|---|
| `check_1_identity` | slot `identity_confirmed` | `min_sources: 1` (single high-grade match suffices when grade ≥ B). |
| `check_2_role` | slot `current_role` | High-stakes — `min_sources: 2`, `max_age_days: 365`. |
| `check_3_platforms` | slot `public_platforms` | `min_sources: 2` is the "at least 2" semantics. |
| `check_4_contact` | slot `contact_method` | |
| `check_5_career` | slot `career_history` | `min_sources: 2` is the "2+ positions" semantics. |
| `check_6_location` | slot `current_location` | `max_age_days: 365` because location goes stale. |
| `check_7_photo` | slot `photograph` | `min_grade: D` — any reasonable photo source suffices. |
| `check_8_contradictions` | `meta_checks.contradictions_resolved` | Process attestation, not data coverage. Per spec §3.2 / §4.5. |
| `check_9_internal` | `meta_checks.phase_2_attested` | Process attestation. Reads `stages/02-internal.gates.log` (R19) — terminal gate-state ⇒ `promoted` / `skipped`; partial ⇒ `incomplete`. Phase 5 (psychoprofile) is a separate, optional axis with no Phase-6 attestation today. |
