---
allowed-tools:
  - Bash(perplexity:*)
  - Bash(exa:*)
  - Bash(tavily:*)
  - Bash(jina:*)
  - Bash(apify:*)
  - Bash(brightdata:*)
  - Bash(parallel-cli:*)
  - Bash(.claude/skills/osint-dossier/scripts/check-tools.sh:*)
  - Bash(.claude/skills/osint-dossier/scripts/first-volley.sh:*)
  - Bash(.claude/skills/osint-dossier/scripts/merge-volley.sh:*)
  - Bash(.claude/skills/osint-dossier/scripts/spend-add.sh:*)
  - Bash(.claude/skills/osint-dossier/scripts/spend-total.sh:*)
  - WebSearch
  - WebFetch
  - Read
  - Write(./osint-*)
  - Write(./osint-*/**)
  - AskUserQuestion
  - Glob
  - Grep
description: >-
  Person-focused OSINT research skill. From a name/handle/URL, build a graded
  public-record dossier with confidence-scored facts and explicit gaps.
  Triggers: "osint <name>", "profile person", "due diligence on", "dossier on",
  "research person", "background check", "досье", "OSINT".
  NOT for: company/product research without a named person; content generation;
  market analysis; competitive intelligence.
argument-hint: <person name or handle> [context keywords]
---

# osint-dossier — Graded Public-Record Dossier

**What it does.** Starts from a person's name, handle, or URL. Produces a dossier:
every fact comes with a confidence grade, a source, and — when relevant — an
explicit "verify this" path. Gaps are listed as gaps, not papered over. Internal
signals (your own chat/email history with the subject) are gated behind an
explicit human approval and never quoted verbatim.

**Input:** `$ARGUMENTS` — person name/handle, optionally followed by context
keywords (company, city, role) to disambiguate.

**Output:** a dossier markdown file written to `./osint-<subject-slug>/dossier.md`.
All paths in this skill are **relative to the operator's working directory at
skill launch** (`$PWD`). The skill never writes outside that subtree.

---

## Stage artifacts

Every phase persists its structured output to
`./osint-<slug>/stages/` so a run is auditable and resumable. Filename
convention (one artifact per phase):

| Phase | Path | Shape |
|---|---|---|
| 0 | `stages/00-tooling.json` | preflight: CLIs available, env vars set, `has_search` bool |
| 1 | `stages/01-seed.json` | merged search results (written by `merge-volley.sh`) |
| 2 | `stages/02-internal.gates.log` | 4-gate audit trail — gate state only, **not** content |
| 3 | `stages/03-platform-<platform>.json` | one file per platform queried (linkedin, instagram, …) |
| 4 | `stages/04-cross-ref.json` | graded fact list pre-render (same shape as `dossier.facts.jsonl` plus working notes) |
| 5 | `stages/05-psychoprofile.json` | only if Phase 5 ran |
| 6 | `stages/06-gaps.json` | gap list with where-and-how |
| 7 | `dossier.md` + `dossier.facts.jsonl` | top-level (canonical paths from R12) |

Rules:
- Each phase writes its stage artifact **before** the phase is considered
  complete. If a write fails, the phase fails — do not proceed.
- **Phase 2 content is never persisted under `stages/`.** Only the gate
  state log is. The redactable content file `phase-2-raw.md` stays at the
  top level under operator control (per the 4-gate protocol). This is the
  core security invariant — do not relax it.
- Scratch intermediates (`volley-*.json`, `seed-summary.md`, `phase-2-raw.md`,
  `content/<…>.md`, `spend.jsonl`) stay at the top level. `stages/` holds
  only the structured per-phase artifacts.
- A run interrupted between Phase N and N+1 can be resumed: re-invoke the
  skill and instruct it to start at Phase N+1, reading
  `stages/0N-*.json` for input.

---

## Tool layer

This skill **does not call HTTP APIs directly**. It shells out to typed CLIs
that validate input, enforce rate limits, redact secrets, and return JSON on
stdout. The CLIs are the security boundary — the skill's job is orchestration.

| CLI | Status on this host | Env var |
|---|---|---|
| `perplexity` | local (own CLI, see roadmap at `~/src/CLI-tools-ROADMAP.md`) | `PERPLEXITY_API_KEY` |
| `exa` | local (own CLI, planned) | `EXA_API_KEY` |
| `tavily` | local (own CLI, planned) | `TAVILY_API_KEY` |
| `jina` | official — `jina-ai/cli` | `JINA_API_KEY` |
| `apify` | official — `apify-cli` | `APIFY_TOKEN` or `APIFY_API_TOKEN` |
| `brightdata` | official — `@brightdata/cli` | `BRIGHTDATA_API_KEY` (or MCP URL) |

Every CLI returns a JSON envelope of the shape:

```json
{ "schema_version": "1", "provider": "...", "command": "...", "result": { ... }, "citations": [...] }
```

If a CLI is missing or misconfigured, the skill surfaces a clear install hint —
it does not silently fall back.

---

## Research escalation — cost tiers

Use the cheapest tier that can fill a slot. Ascend only when Phase
6 marks a slot as `escalation_eligible` and the next un-tried tier
on its `tier_ladder` can mechanically close it. Never escalate as
the default.

**Read protocol.**

1. Read `schema_version` from `./osint-<slug>/stages/06-gaps.json`
   first. If absent or not `"2"`, stop with the error: *Phase 6
   artifact schema mismatch — see references/phase-6-spec.md §2 O2*.
   Do not proceed.
2. Iterate `escalation_eligible[]`. For each `slot_id` therein,
   look up the slot's row in `slots[]` and the slot's `tier_ladder`
   in `references/slots.md`. Pick the **first un-tried tier** —
   i.e., the first entry of `tier_ladder` not present in
   `tiers_tried`.
3. Run that tier's tool against the slot's `where_and_how`. Append
   the tier you ran to that slot's `tiers_tried[]` in
   `06-gaps.json` (set semantics — don't append if already present;
   serialized as ordered list to preserve attempt order). This is
   the only place R18 mutates `06-gaps.json`. Phase 6's next cycle
   reads the post-R18 state.
4. Slots NOT in `escalation_eligible[]` are off-limits — that
   includes ladder-exhausted unmet slots (where every tier has been
   tried) and any `meta_checks{}` entry. Escalation cannot fix
   contradictions or attestation state.

| Tier | Cost / call | Providers |
|---|---|---|
| L1 | ~$0 | `WebSearch`, `perplexity` (sonar), `exa search`, `tavily` (basic) |
| L2 | ~$0.01 | `jina read`, `tavily extract` |
| L3 | ~$0.05–0.10 | `apify call <id>` per-platform extraction |
| L4 | ~$0.50–$5 | `perplexity` (deep), `exa` (deep), `parallel-cli` (deep) |

Phases 1 and 3 default to L1–L3 by construction. L4 is reserved for
gap-targeted re-runs as above. The budget cap (≤ $0.50, see "Budget &
stopping") still applies — a single L4 call can already meet or exceed
the cap (Perplexity Deep in particular runs in the multi-dollar
range), so escalate one slot at a time and check `spend-total.sh`
before fanning out.

---

## Phase 0 — Preflight

1. Run `bash .claude/skills/osint-dossier/scripts/check-tools.sh` once. Log which
   CLIs are available.
2. Parse `$ARGUMENTS`. Extract: `subject_name`, optional `context` list
   (company, city, role).
3. Create the work folder and stage subdir: `./osint-<subject-slug>/stages/`
   (slug = lowercase name, ASCII, hyphens for spaces).
4. If no `subject_name` — use `AskUserQuestion` to collect one. Never guess.
5. Decide the minimum viable toolset for this run:
   - Need ≥ 1 of: `perplexity`, `tavily`, `exa`, `jina`, or built-in `WebSearch`.
6. **Persist the stage artifact** (always, including on toolset failure —
   the file is the diagnostic record of the early-stop). `Write`
   `./osint-<slug>/stages/00-tooling.json`:
   ```json
   {"schema_version":"1","phase":0,"clis_available":["perplexity","jina"],
    "env_vars_set":["PERPLEXITY_API_KEY","JINA_API_KEY"],"has_search":true,
    "subject_name":"<name>","context":["..."],"slug":"<slug>","ts":"<ISO>"}
   ```
7. If `has_search` is false — stop and report. The 00-tooling.json artifact
   is left on disk so the operator can see exactly which CLIs/env vars
   were missing.

---

## Phase 1 — Seed Collection (external only)

**Goal:** build a first-pass fact sheet from **public** sources. No internal
data touched in this phase.

1. **Preferred:** run the wrapper
   `bash scripts/first-volley.sh "$subject_name" $context`. It fans out one
   background call per available CLI (perplexity / exa / jina / tavily),
   staggers starts by 0.5 s, applies a per-job 60 s timeout, and writes
   `./osint-<slug>/volley-<provider>.json` per provider (these are scratch
   intermediates, not stage artifacts). Then run
   `bash scripts/merge-volley.sh "$slug"` to dedup by canonical URL and emit
   `./osint-<slug>/stages/01-seed.json` in the unified
   `{schema_version, merged_from, rows[], answers[]}` shape — this is the
   Phase 1 stage artifact.
   **Manual fallback** (if the wrappers are unavailable): run up to 4
   parallel CLI calls yourself, then merge by hand. If no typed search
   CLI is available at all, fall back to Claude Code's built-in
   `WebSearch` (Brave-backed) for at least one Phase-1 query. WebSearch
   output counts as a Phase-1 result for Anti-pattern #1 ("never start
   Phase 3 without at least one Phase 1 result"); it is just lower
   confidence than typed-CLI output.
2. After each external call, log spend with
   `bash scripts/spend-add.sh <envelope.json> "$slug"` so the Phase 7 audit
   line is sourced from `./osint-<slug>/spend.jsonl` instead of guesswork.
3. If the result set looks ambiguous (two people with the same name, or
   wildly conflicting snippets) — use `AskUserQuestion` to pick the
   correct entity. **Do not** auto-disambiguate.
4. Compose a 5–8 line preliminary summary. Save it as
   `./osint-<slug>/seed-summary.md`.
5. Decide: proceed to Phase 2 (internal intel) or skip directly to Phase 3
   (platforms). Default: ask the operator via `AskUserQuestion`.
6. **Stage artifact:** `stages/01-seed.json` (already written by
   `merge-volley.sh` in step 1). If you fell back to the manual path or
   `WebSearch`, `Write` `./osint-<slug>/stages/01-seed.json` yourself in
   the same `{schema_version, merged_from, rows[], answers[]}` shape.

**Rate-limiting rule:** no more than 4 concurrent outbound calls across this
whole phase (one per available search CLI). Staggered starts of 0.5 s.
Per-job timeout 60 s. Never hammer a single provider with parallel calls.

---

## Phase 2 — Internal Intelligence (HUMAN-GATED, 4-gate promotion)

Before any of this runs, **read** `references/phase-2-gates.md`. This phase
touches your own local data (chat history, email, vault) and is behind four
explicit gates. If any gate fails, the phase stops and Phase 3 proceeds
**without** internal data.

### Gate 1 — Pre-execution approval
Use `AskUserQuestion` with the exact question:

> *"About to query local sources for subject `<name>`. I will search
> Telegram history (if available), email inbox (if available), and
> `vault/crm/*.md` (if that folder exists). Results will go to a file for
> your review. Nothing is pulled into the dossier without your explicit
> approval. Proceed?"*

Options: `yes — proceed` / `skip internal — go to Phase 3` / `cancel`.
Any answer other than `yes` skips Phase 2 entirely.

### Gate 2 — Write raw results to file (no context inhalation)
If Gate 1 passed:

1. Run the configured queries (Telegram / email / vault). Capture the **raw**
   results.
2. `Write` them to `./osint-<slug>/phase-2-raw.md` in a structured,
   redactable shape. Each finding carries a placeholder:
   ```
   ### Finding 1
   - Source: telegram (<chat_name>, <date>)
   - Subject mentioned: yes
   - Raw excerpt: [REDACTION_NEEDED — operator review pending]
   - Auto-summary (safe): <one sentence, no verbatim quotes>
   ```
3. **Do not load the raw content into the agent's own context.** The tool-use
   must `Write` and stop — not `Read`-back the raw excerpts. The agent only
   sees counts + auto-summary, never the DM text.
4. Report to the operator: file saved, N findings, time elapsed.

### Gate 3 — Operator redaction window
Use `AskUserQuestion`:

> *"Phase-2 raw file is at `./osint-<slug>/phase-2-raw.md`. Open it,
> redact anything you do not want to appear in the dossier (replace with
> `[REDACTED]`), and replace every `[REDACTION_NEEDED — …]` marker with
> either the approved excerpt, an `[INDIRECT: <one-line paraphrase>]`
> placeholder, or `[DROP]`. When done, add this exact line at the end of
> the file: `PROMOTION: APPROVED <your-initials> <ISO-date>`. Reply
> `approved` when saved."*

Options: `approved` / `skip internal — go to Phase 3` / `still redacting`.
Only `approved` proceeds. `still redacting` loops the question after 2 min.

### Gate 4 — Promotion check
Before reading the promoted file:

1. `Read` `./osint-<slug>/phase-2-raw.md`.
2. Verify the file ends with a line matching `^PROMOTION: APPROVED \S+ \d{4}-\d{2}-\d{2}$`.
3. Verify no line still contains the literal string `REDACTION_NEEDED`.
4. If either check fails — stop Phase 2, skip to Phase 3, and note in the
   dossier: *"Internal intel: not promoted (gate 4 failed)."*

### Usage rules for promoted internal data
- **Never** quote verbatim in the final dossier.
- Wherever internal data shaped a claim, the dossier cites
  `[internal, operator-approved 2026-XX-XX]` — not the message content.
- Internal data does **not** count as an independent source for grading
  (it's tagged Grade "I" — internal, operator-approved, not cross-referenced).
- Audit log line added to the dossier: *"Internal intelligence consulted:
  yes, approved YYYY-MM-DD. Sources: <channels>, N findings promoted."*

### Stage artifact

`stages/02-internal.gates.log` — append-only audit trail of gate state
transitions. Lines are ASCII-safe and contain **no content** from
internal sources, only gate decisions.

The first line on every skill invocation that enters Phase 2 is a
run-start delimiter so re-runs don't interleave silently:

```
# run-start <ISO-8601-UTC> slug=<slug>
<ISO-8601-UTC> gate-1 result=<yes|skip|cancel|n/a>
<ISO-8601-UTC> gate-2 written findings=<N>
<ISO-8601-UTC> gate-3 result=<approved|skip|still-redacting>
<ISO-8601-UTC> gate-4 result=<passed|failed-regex|failed-redaction-marker|failed-missing-file>
```

Append one line per gate decision as you reach it. Phase 2 raw findings
go to `./osint-<slug>/phase-2-raw.md` (operator workspace) — **never** to
`stages/`.

---

## Phase 3 — Platform Extraction

**Goal:** Pull structured profile data from platforms where the subject has
a footprint. Each platform has a primary CLI + a fallback.

Primary → fallback chains (switch immediately on a failure; do not retry the
same tool):

- LinkedIn: `apify call <linkedin-actor> --input …` → `brightdata scrape <url>` → `jina read <url>`
- Instagram: `apify call <instagram-actor>` → `brightdata scrape`
- Facebook (personal): `brightdata scrape` (others blocked) → stop
- Facebook (pages/groups): `apify call <fb-pages-actor>` → `brightdata scrape`
- TikTok: `apify call <tiktok-actor>` → `brightdata scrape`
- YouTube: `apify call <youtube-channel-actor>` → `jina read` → `brightdata scrape`
- Telegram channels (public): `WebFetch t.me/s/<channel>` → `jina read`
- Any other site: `jina read <url>` → `brightdata scrape <url>`

Read `references/platforms.md` **only** when needing URL patterns or extraction
signals for a specific platform. For Apify actor IDs / input shapes / typical
costs per platform, read `references/tools.md`. For pulling clean text out
of YouTube / podcasts / blog / talks, read `references/content-extraction.md`.

### Stage artifact (per platform)
For every platform queried, `Write`
`./osint-<slug>/stages/03-platform-<platform>.json` with the structured
extraction output. Schema:

```json
{"schema_version":"1","phase":3,"platform":"linkedin",
 "subject_slug":"<slug>","queries":[{"url":"...","cli":"apify","cost_usd":0.05}],
 "rows":[{"slot_id":"<catalog-slot-id-or-null>","date":"<YYYY-MM-DD-or-null>","...platform-specific fields...}],
 "errors":[],"ts":"<ISO>"}
```

Writing one file per platform (instead of one combined file) lets the
opt-in fan-out path (R8) write each cluster independently with no
merge step.

**Per-row tagging (R20 / Phase 6 v2 precondition).** Every row in
`rows[]` carries:

- `slot_id` — the catalog slot from `references/slots.md` this row
  attests, or `null` if the row doesn't map to any slot. Pick the
  most specific match. Don't invent IDs not present in the catalog.
  When in doubt between two slots, set `null` and let the operator
  triage at Phase 6 review.
- `date` — best-available ISO date (`YYYY-MM-DD`) the source
  attested the claim: profile-last-updated for LinkedIn, publish
  date for press releases, geotag time for posts. If unknown, set
  `null` — Phase 6 treats `null` dates as failing any
  `max_age_days` gate (conservative).

Phase 4 carries both fields through unchanged onto each fact it
emits.

### Content-platform rule
When a YouTube / podcast / blog / conference talk is found — extract
transcripts on the spot (don't just note the URL). Content platforms are the
#1 source for voice and topic signal. Store transcript text under
`./osint-<slug>/content/<platform>-<id>.md` (scratch intermediate, not a
stage artifact — the structured row in `03-platform-<platform>.json`
references the transcript path).

### Fan-out option (optional, default off)
If you are working on a subject with a large footprint and the operator has
explicitly asked for faster collection, you MAY split Phase 3 across 3–5
parallel sub-agents (one per platform cluster). Rules:

1. Each sub-agent gets **only** what it needs: subject name, handle, 1–2
   context keywords. **Never** pass Phase-2 content to sub-agents.
2. Each sub-agent writes its output to
   `./osint-<slug>/stages/03-platform-<name>.json` (same convention as the
   sequential path — fan-out is just parallelism, not a different shape).
3. Main agent waits for all workers, merges, proceeds to Phase 4.
4. Each worker's budget: ≤ $0.15. Total fan-out budget: ≤ $0.50.
5. Fan-out is opt-in; default is sequential.

---

## Phase 4 — Cross-Reference & Fact Grading

For every claim collected so far, assign a grade. Grades:

- **A — confirmed.** ≥ 2 independent public sources agree, or official verified
  profile (LinkedIn verified, government site), or direct public statement.
- **B — probable.** One credible source (LinkedIn, official media, company
  site).
- **C — inferred.** Indirect evidence (timezone from post times, geotag,
  2nd-degree connections).
- **D — unverified.** Single low-credibility mention.
- **I — internal, operator-approved.** From Phase 2, indirect paraphrase only,
  never counts toward A-grade confirmation.

### Contradiction handling
If two sources disagree (LinkedIn says "CEO", company site says "Co-founder")
— list both in the dossier with their sources. Do not silently pick one.

### Name-collision check
If the name is common, require at least 2 facts (e.g., company + city, or
photo + role) linking to the same entity. If unsure, split into separate
entries.

### Stage artifact
`Write` `./osint-<slug>/stages/04-cross-ref.json` — the graded fact list
pre-render. Same shape as `dossier.facts.jsonl` (one fact per object) but
as a single JSON document plus working notes:

```json
{"schema_version":"2","phase":4,
 "facts":[{"fact_id":"fact_1","slot_id":"<catalog-slot-id-or-null>","claim":"...","grade":"A","sources":["..."],"date":"<YYYY-MM-DD-or-null>","notes":""}],
 "contradictions":[{"claim_a":"...","claim_b":"...","sources":["...","..."]}],
 "name_collision":{"checked":true,"resolved":true,"evidence":["..."]},
 "ts":"<ISO>"}
```

This is the input to Phase 6 (gap analysis) and Phase 7 (render). Re-running
either phase in isolation reads from this file.

**Fact fields required by Phase 6 v2 (R20):**

- `fact_id` — assign a stable snake_case id (`fact_1`, `fact_2`, …)
  in append order. Phase 6's `06-gaps.json[].slots[].evidence[]`
  references these. IDs must be unique within a single
  `04-cross-ref.json`.
- `slot_id` — copy through from the originating Phase 3 row's
  `slot_id` (or set `null` for facts that don't map to any catalog
  slot — a contradiction note, a name-collision artefact). Do not
  invent slot IDs; check `references/slots.md` for the canonical
  list.
- `date` — copy through from the originating Phase 3 row's `date`
  (ISO `YYYY-MM-DD` or `null`). Phase 6's `max_age_days` gate reads
  this.

For Grade-I facts (Phase 2 internal-promoted), `slot_id` is set the
same way; whether the slot accepts the I-grade fact is governed by
the slot's `internal_counts` flag (default `false`) — Phase 6
enforces non-substitution mechanically. Phase 4 does NOT pre-filter.

`schema_version` bumped from `"1"` to `"2"` to mark the field
additions. Re-running Phase 7 against a v1 `04-cross-ref.json` is
unsupported (clean break per ROADMAP R20 §1.4).

---

## Phase 5 — Psychoprofile (optional, read `references/psychoprofile.md` first)

Skip unless the operator asked for it. When run, use only public text
samples: posts, bios, interviews, public talks. Output is:
MBTI per dimension with cited behavioural evidence + confidence (high /
medium / low). Writing-style metrics: avg. sentence length, self-reference
rate, emoji density.

Never infer family, DOB, or zodiac unless confirmed at grade A or B.

### Stage artifact
If Phase 5 ran, `Write`
`./osint-<slug>/stages/05-psychoprofile.json`:

```json
{"schema_version":"1","phase":5,
 "mbti":{"E_I":{"value":"I","confidence":"medium","evidence":["..."]}, "...":{}},
 "writing_style":{"avg_sentence_len":14.2,"self_reference_rate":0.08,"emoji_density":0.01},
 "samples_used":["<url>","<url>"],"ts":"<ISO>"}
```

If Phase 5 was skipped, do not create the file (its absence is the signal).

---

## Phase 6 — Completeness & Gap Analysis

Phase 6 v2 (R20, schema_version `"2"`) is a deterministic function:
`(stages/04-cross-ref.json, references/slots.md, prior-cycle stages/06-gaps.json) → new stages/06-gaps.json`.
The slot catalog (`references/slots.md`) is the single source of
truth for **what** Phase 6 evaluates — adding/removing a check is a
catalog edit, not a SKILL.md edit. The full spec is in
`references/phase-6-spec.md`.

### Procedure

1. **Load and filter the catalog.** Read `references/slots.md`. For
   each slot row, evaluate `applies_when` against the run context
   (which phases ran). Drop rows that evaluate false; count them
   into `summary.applies_when_skipped`. Surviving rows in catalog
   declaration order = the slot list for this cycle.

2. **Attach Phase 4 facts to slots.** Read
   `stages/04-cross-ref.json`. For each surviving slot, collect
   facts whose `slot_id` matches. Facts with `slot_id: null`
   contribute to no slot.

3. **Compute eligibility, then `met` per slot.** For each fact:
   - `passes_grade(f) ::= (f.grade ∈ {A,B,C,D} AND f.grade ≥ slot.min_grade) OR (f.grade == "I" AND slot.internal_counts == true)`
     where the A/B/C/D ordering is `A > B > C > D`. Grade I is a
     separate axis governed only by `internal_counts` — never
     ordered against A/B/C/D. The default `internal_counts: false`
     enforces non-substitution per spec S1.1.
   - `passes_freshness(f) ::= slot.max_age_days unset OR (f.date != null AND f.date ≥ today - slot.max_age_days)`
   - `eligible(f) ::= passes_grade(f) AND passes_freshness(f)`
   - `met ::= count(eligible facts) ≥ slot.min_sources`

4. **Derive `kind` per slot.** If `met`, `kind = "met"`. Otherwise
   walk top-down, first match wins:

   | Order | Kind | Condition |
   |---|---|---|
   | 1 | `never_found` | No facts attached. |
   | 2 | `low_grade` | No fact passes grade (covers Grade-I-only with `internal_counts: false`). |
   | 3 | `stale` | `max_age_days` declared AND ≥1 fact passes grade AND none also passes freshness. |
   | 4 | `undersourced` | Otherwise (≥1 eligible fact but count < `min_sources`). |

5. **Build the artifact.** For each slot, render `where_and_how`
   from the catalog template by substituting the variables in the
   catalog header (literal substitution, no conditionals). Carry
   forward `tiers_tried` from prior cycle's row of the same
   `slot_id` (cycle 1: empty list; if R18 ran between cycles it
   already appended in place per its own contract). Compute
   `escalation_eligible[]` as the slot_ids whose `met == false`
   AND whose `tier_ladder \ tiers_tried` is non-empty. Compute
   `meta_checks{}` (see below). Compute `summary{}` counts.
   Compute `stop_decision` (see below). `Write` the artifact with
   `schema_version: "2"` as the FIRST key.

### Stage artifact

`Write` `./osint-<slug>/stages/06-gaps.json`:

```json
{"schema_version":"2","cycle":1,
 "slots":[
   {"slot_id":"<id>","met":false,"kind":"undersourced",
    "where_and_how":"<rendered template>",
    "tiers_tried":[],"evidence":["fact_42"]}
 ],
 "escalation_eligible":["<id>"],
 "meta_checks":{
   "contradictions_resolved":true,
   "phase_2_attested":"skipped"
 },
 "summary":{"met":5,"unmet_with_ladder":2,"unmet_ladder_exhausted":0,"applies_when_skipped":0},
 "stop_decision":"continue",
 "timestamp":"<ISO>"}
```

Two summary invariants must hold every cycle:
`met + unmet_with_ladder + unmet_ladder_exhausted == len(slots)` and
`len(slots) + applies_when_skipped == len(catalog)`.

### Meta-checks (process attestation)

`meta_checks{}` is NOT slots and NOT in `escalation_eligible[]` —
escalation cannot fix Phase 4's contradiction count or Phase 2's
gate-state.

- `contradictions_resolved` (bool) — `true` iff
  `04-cross-ref.json.contradictions[]` is empty.
- `phase_2_attested` (enum `promoted` / `skipped` / `incomplete`) —
  derived from `stages/02-internal.gates.log`. Terminal gate-state
  ⇒ `promoted` or `skipped` (per Gate 1's
  `yes — proceed` / `skip internal — go to Phase 3` answer).
  `incomplete` ⇒ Phase 2 started but did not reach a terminal gate.

### Stopping criteria

Evaluated in order; first match wins:

1. `04-cross-ref.json.facts[]` empty → `render-with-note` (zero-facts edge).
2. All slots `met == true` → `render-final`.
3. `cycle == 3` → `render-final` (cycle cap).
4. `cycle > 1` AND `summary.met` did not increase since prior cycle
   → `render-final` (plateau).
5. Otherwise → `continue`.

### Schema-version handshake (per spec O2)

When reading any `stages/06-gaps.json` written in a prior cycle (or
by a prior run), read `schema_version` first. If absent or not
`"2"`, stop with the error: *Phase 6 artifact schema mismatch — see
references/phase-6-spec.md §2 O2*. Do not synthesize defaults.

Phase 7 reads `06-gaps.json` to render Gaps + Coverage. Re-running
Phase 7 from a written `06-gaps.json` is supported per R19.

---

## Phase 7 — Dossier Rendering

Render the final dossier to `./osint-<slug>/dossier.md` by filling the
placeholders in `assets/dossier-template.md`. Rules and grade legend are
embedded in the template's HTML comment header — do not duplicate them here.

**Read protocol for `stages/06-gaps.json`.** Read `schema_version`
first. If absent or not `"2"`, stop with the error: *Phase 6 artifact
schema mismatch — see references/phase-6-spec.md §2 O2*. Do not
proceed. The template's Gaps section is filled from `slots[]` rows
where `met == false`. Distinguish render affordances:

- `tiers_tried` is empty → "not yet attempted" (operator next-move
  signal).
- `set(tiers_tried) == set(slot.tier_ladder)` → "tried all tiers, no
  result" (operator: spending more here is probably wasted).
- Otherwise → standard gap with the catalog-rendered `where_and_how`.

The Coverage block reports met-count + per-grade distribution
(derived by counting each met slot's strongest evidence grade) — there
is no `depth_score` in v2.

The Audit footer adds the `meta_checks{}` block: render
`contradictions_resolved` and `phase_2_attested` verbatim. Only
`phase_2_attested == "incomplete"` triggers a warning surface;
`promoted` and `skipped` are both valid attestations.

**Also emit a machine-readable sidecar** `./osint-<slug>/dossier.facts.jsonl`
— one JSON object per line, 1-to-1 with the dossier's Facts list. Schema:

```json
{"schema_version":"1","claim":"<string>","grade":"A|B|C|D|I","sources":["<url>","<url>"],"notes":""}
```

For Grade-I (internal) facts, omit `sources` and include
`"internal":{"approved":"YYYY-MM-DD"}` instead. The sidecar lets
downstream tools verify, re-grade, or graph-merge facts across dossiers
without re-running the skill.

Source the audit-log spend total from `bash scripts/spend-total.sh "$slug"`
(returns `{total_usd, calls, providers}` JSON), and the elapsed time from
the wall-clock between Phase 0 start and Phase 7 render.

The audit log's `Stage manifest` field is a **comma-separated list of
relative paths** (relative to `./osint-<slug>/`), one per artifact that
the run actually produced. Example:

```
Stage manifest: stages/00-tooling.json, stages/01-seed.json, stages/02-internal.gates.log, stages/03-platform-linkedin.json, stages/04-cross-ref.json, stages/06-gaps.json
```

Skipped phases (e.g. Phase 5 when psychoprofile wasn't requested) do
not appear. The dossier file itself stays at the canonical top-level
path (`./osint-<slug>/dossier.md`, `./osint-<slug>/dossier.facts.jsonl`)
— no mirror under `stages/`, and not listed in the manifest.

---

## Budget & stopping

- ≤ $0.50 per subject without asking.
- \> $0.50 — stop and ask the operator.
- Per-call cost is tracked from CLI output (`cost_usd` in the envelope) and
  appended to `./osint-<slug>/spend.jsonl` via `scripts/spend-add.sh`.
- Running total at any time: `bash scripts/spend-total.sh "$slug"`.

---

## Anti-patterns (do not)

1. Never start Phase 3 without at least one Phase 1 result.
2. Never retry a failed CLI twice. Switch to the fallback.
3. Never attribute a claim to the subject without passing the name-collision
   check.
4. Never quote internal/private data verbatim in any output.
5. Never skip the 4-gate protocol for Phase 2, even "just this once".
6. Never fan out when the subject has a small footprint (wastes $$$).
7. Never infer family, DOB, zodiac without Grade A/B source.
8. Never rate Depth Score ≥ 9 without naming the 2+ cross-references that
   justify it.
9. Never cite an aggregator when the primary source is one click away.
10. Never include unsourced facts in the dossier.

---

## Security posture

- This skill runs with a narrow `allowed-tools` list (see the frontmatter).
- It does not write outside `./osint-*` (CWD-relative; never `/tmp` or `~`).
- API keys come from env vars — the CLI binaries refuse if the env var is
  missing. The skill itself never sees or logs the key.
- Scraped content from Phase 3 is treated as untrusted — the skill does not
  pass raw scraped strings into further CLI calls without sanitisation.
  (Rule: when a field comes from an external fetch, it is only passed as a
  **parameter** to a typed CLI, never as part of a query string we build
  from scratch.)
- Internal data is behind four gates. If you are tempted to add a fifth
  bypass "just for this one case" — don't.

---

## See also

- `README.md` — install + first-run walkthrough.
- `DESIGN.md` — architectural decisions: why 4 gates, why fan-out is off by
  default, why CLIs instead of curl wrappers.
- `references/phase-2-gates.md` — the gate protocol in detail with edge cases.
- `references/platforms.md` — URL patterns per platform (lazy-loaded at
  Phase 3).
- `references/tools.md` — Apify actor catalog: IDs, input shapes, typical
  costs (lazy-loaded at Phase 3).
- `references/content-extraction.md` — how to pull transcripts / clean text
  from YouTube, podcasts, blogs, talks (lazy-loaded at Phase 3).
- `references/psychoprofile.md` — MBTI/Big Five methodology (lazy-loaded at
  Phase 5).
- `assets/dossier-template.md` — fillable Phase 7 output template.
- `scripts/first-volley.sh`, `scripts/merge-volley.sh` — Phase 1 fan-out + merge
  (writes `stages/01-seed.json`).
- `scripts/spend-add.sh`, `scripts/spend-total.sh` — Phase 7 cost ledger.
