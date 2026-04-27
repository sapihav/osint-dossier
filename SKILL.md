---
allowed-tools:
  - Bash(perplexity:*)
  - Bash(exa:*)
  - Bash(tavily:*)
  - Bash(jina:*)
  - Bash(apify:*)
  - Bash(brightdata:*)
  - Bash(parallel:*)
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

## Phase 0 — Preflight

1. Run `bash .claude/skills/osint-dossier/scripts/check-tools.sh` once. Log which
   CLIs are available.
2. Parse `$ARGUMENTS`. Extract: `subject_name`, optional `context` list
   (company, city, role).
3. Create the work folder: `./osint-<subject-slug>/` (slug = lowercase
   name, ASCII, hyphens for spaces).
4. If no `subject_name` — use `AskUserQuestion` to collect one. Never guess.
5. Decide the minimum viable toolset for this run:
   - Need ≥ 1 of: `perplexity`, `tavily`, `exa`, `jina`, or built-in `WebSearch`.
   - If none are available, stop and report.

---

## Phase 1 — Seed Collection (external only)

**Goal:** build a first-pass fact sheet from **public** sources. No internal
data touched in this phase.

1. **Preferred:** run the wrapper
   `bash scripts/first-volley.sh "$subject_name" $context`. It fans out one
   background call per available CLI (perplexity / exa / jina / tavily),
   staggers starts by 0.5 s, applies a per-job 60 s timeout, and writes
   `./osint-<slug>/volley-<provider>.json` per provider. Then run
   `bash scripts/merge-volley.sh "$slug"` to dedup by canonical URL and emit
   `./osint-<slug>/seed.json` in the unified
   `{schema_version, merged_from, rows[], answers[]}` shape.
   **Manual fallback** (if the wrappers are unavailable): run up to 4
   parallel CLI calls yourself, then merge by hand.
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

### Content-platform rule
When a YouTube / podcast / blog / conference talk is found — extract
transcripts on the spot (don't just note the URL). Content platforms are the
#1 source for voice and topic signal. Store transcript text under
`./osint-<slug>/content/<platform>-<id>.md`.

### Fan-out option (optional, default off)
If you are working on a subject with a large footprint and the operator has
explicitly asked for faster collection, you MAY split Phase 3 across 3–5
parallel sub-agents (one per platform cluster). Rules:

1. Each sub-agent gets **only** what it needs: subject name, handle, 1–2
   context keywords. **Never** pass Phase-2 content to sub-agents.
2. Each sub-agent writes its output to
   `./osint-<slug>/platform-<name>.md`.
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

---

## Phase 5 — Psychoprofile (optional, read `references/psychoprofile.md` first)

Skip unless the operator asked for it. When run, use only public text
samples: posts, bios, interviews, public talks. Output is:
MBTI per dimension with cited behavioural evidence + confidence (high /
medium / low). Writing-style metrics: avg. sentence length, self-reference
rate, emoji density.

Never infer family, DOB, or zodiac unless confirmed at grade A or B.

---

## Phase 6 — Completeness & Gap Analysis

### Coverage (9 checks — pass/fail)

1. Subject correctly identified (not a namesake)?
2. Current role/organisation confirmed?
3. At least 2 public platforms with profile?
4. At least 1 contact method (public)?
5. Career history: 2+ verifiable positions?
6. Current location established?
7. At least 1 photograph found?
8. No unresolved contradictions between sources?
9. Internal intelligence phase: either run-and-promoted or explicitly skipped?

### Depth score (weighted, 1–10)

| Dimension | Weight | Score |
|---|---|---|
| Identity | 0.15 | … |
| Career | 0.20 | … |
| Digital footprint | 0.15 | … |
| Psychoprofile (if run) | 0.10 | … |
| Cross-reference strength | 0.15 | … |
| Actionability (entry points) | 0.10 | … |
| Recency (dates < 12 months) | 0.15 | … |

Weighted sum → `Depth Score`.

### Stopping criteria
- Depth Score ≥ 8 AND all coverage checks pass → Phase 7 (render).
- 3 cycles exhausted → render best available with an honest "Insufficient"
  note.
- Two cycles with delta < 0.5 → plateau reached; render with note.

### Gap list (always)
Every gap in the dossier includes a **where-and-how** — which public register,
which platform, which search — not just "missing".

---

## Phase 7 — Dossier Rendering

Render the final dossier to `./osint-<slug>/dossier.md` by filling the
placeholders in `assets/dossier-template.md`. Rules and grade legend are
embedded in the template's HTML comment header — do not duplicate them here.

Source the audit-log spend total from `bash scripts/spend-total.sh "$slug"`
(returns `{total_usd, calls, providers}` JSON), and the elapsed time from
the wall-clock between Phase 0 start and Phase 7 render.

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
- `scripts/first-volley.sh`, `scripts/merge-volley.sh` — Phase 1 fan-out + merge.
- `scripts/spend-add.sh`, `scripts/spend-total.sh` — Phase 7 cost ledger.
