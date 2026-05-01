# Changelog

## v0.4.2 — 2026-05-01

R18 follow-up — escalation rule grounded in existing schema.

- The R18 rule referenced "high-priority" gaps, but
  `stages/06-gaps.json` has no `priority` field — the agent had
  nothing to filter on. Rewrote the rule to derive eligibility from
  `coverage.failed[]` (which Phase 6 already populates):
  > **Ascend only when Phase 6 flags an unfilled gap whose closure
  > would flip a failed coverage check, and the next tier can
  > plausibly close it.**
- A gap is escalation-eligible iff it maps to an entry in
  `coverage.failed[]`. Gaps tied only to depth-score shortfalls do
  not justify L4 spend.
- No schema changes — uses fields Phase 6 already produces. ROADMAP
  R18 entry updated to match.

---

## v0.4.1 — 2026-04-30

R18 closed — research escalation flow.

- New `## Research escalation — cost tiers` section in SKILL.md
  (between "Tool layer" and "Phase 0"). Four cost tiers mapped to
  providers:
  - **L1** (~$0): `WebSearch`, `perplexity` (sonar), `exa search`,
    `tavily` (basic).
  - **L2** (~$0.01): `jina read`, `tavily extract`.
  - **L3** (~$0.05–0.10): `apify call <id>` per-platform extraction.
  - **L4** (~$0.50–$5): `perplexity` (deep), `exa` (deep),
    `parallel-cli` (deep). Perplexity Deep in particular runs in the
    multi-dollar range — a single call can already meet or exceed the
    $0.50 budget cap.
- Single rule: ascend only when Phase 6 flags an unfilled
  high-priority gap that the next tier can plausibly close. Read
  `./osint-<slug>/stages/06-gaps.json` (R19), pick gaps with no
  L1–L3 path that closes them, escalate only those. Budget cap (≤
  $0.50, see "Budget & stopping") still binds — escalate one gap at
  a time and check the spend ledger before fanning out.
- Phases 1 and 3 default to L1–L3 by construction. L4 is for
  gap-targeted re-runs only — no per-level decision trees or
  audit-log changes were added.
- ROADMAP: R18 marked done.

---

## v0.4.0 — 2026-04-29

R19 closed — stage-by-stage artifact persistence.

- **`./osint-<slug>/stages/` filename convention** introduced. Every
  phase now persists its structured output under `stages/` so a run is
  auditable and resumable. One artifact per phase:
  - `00-tooling.json` — Phase 0 preflight (CLIs, env vars, has_search).
  - `01-seed.json` — Phase 1 merged search results (was `seed.json`).
  - `02-internal.gates.log` — Phase 2 4-gate audit trail (state only,
    **no content**).
  - `03-platform-<platform>.json` — Phase 3 per-platform extraction.
  - `04-cross-ref.json` — Phase 4 graded fact list pre-render.
  - `05-psychoprofile.json` — Phase 5 (only if it ran; absence = signal).
  - `06-gaps.json` — Phase 6 coverage / depth / gap list.
  - Phase 7 stays at top-level (`dossier.md`, `dossier.facts.jsonl`).
- **Phase 2 content stays off-disk under `stages/`.** Only the gate
  state log is persisted there. The redactable `phase-2-raw.md` file
  remains at the top level under operator control (4-gate protocol
  unchanged). This is the core security invariant — do not relax.
- Resumability: a run interrupted between Phase N and N+1 can be
  resumed by re-invoking the skill and instructing it to start at
  Phase N+1, reading `stages/0N-*.json` for input.
- `scripts/merge-volley.sh` updated to write
  `./osint-<slug>/stages/01-seed.json` (was `./osint-<slug>/seed.json`)
  and `mkdir -p stages`. Volley scratch files
  (`volley-<provider>.json`) stay at the top level — they are
  intermediates, not stage artifacts.
- `assets/dossier-template.md` audit log gains a `Stage manifest`
  field listing the produced `stages/0N-*` artifacts.
- ROADMAP: R19 marked done.

### Migration notes

- Existing dossiers under `./osint-<slug>/seed.json` are not
  auto-migrated. Re-run the skill or move the file:
  `mkdir -p ./osint-<slug>/stages && mv ./osint-<slug>/seed.json ./osint-<slug>/stages/01-seed.json`.

---

## v0.3.1 — 2026-04-29

R4 closed — Parallel AI typed CLI is now available.

- Added `parallel-cli` to `scripts/install.sh` registry. Install
  method: `curl -sSL https://parallel.ai/install.sh | bash` (the
  upstream installer at `parallel.ai/install.sh` redirects to the
  GitHub release of `parallel-web/parallel-web-tools`). No Python or
  Go required — the standalone binary supports `search`, `extract`,
  `research`, and `enrich`.
- Renamed binary `parallel` → `parallel-cli` in `check-tools.sh`,
  `SKILL.md` frontmatter `allowed-tools` (`Bash(parallel:*)` →
  `Bash(parallel-cli:*)`), and README Dependencies. Matches upstream
  and avoids collision with GNU parallel.
- README Dependencies table gains a `parallel-cli` row.
- ROADMAP: R4 marked done. R19 added (stage-by-stage artifact
  persistence — operator requirement; foundational for R8/R16/R18).

---

## v0.3.0 — 2026-04-29

R1 — install contract.

- **`scripts/install.sh` added.** Installer for every CLI the skill
  expects. Idempotent in the "skip already-present" sense (re-runs are
  safe, tools on PATH are skipped); does not auto-upgrade stale
  versions. Public sources only — no Go toolchain required:
  - `curl -sSL https://raw.githubusercontent.com/sapihav/perplexity-cli/main/install.sh | bash`
  - `curl -sSL https://raw.githubusercontent.com/sapihav/exa-cli/main/install.sh | bash`
  - `curl -sSL https://raw.githubusercontent.com/sapihav/tavily-cli/main/install.sh | bash`
  - `npm install -g apify-cli`
  - `npm install -g @brightdata/cli`
  - `pipx install jina`
  Each repo's `install.sh` detects OS/arch, fetches the latest GitHub
  release binary, drops it under `/usr/local/bin` (overridable via
  `INSTALL_DIR`).
- Modes: default (install missing), `--check` (status report only,
  non-zero exit if any missing), `--line <bin>` (print the install
  command for a single tool — single source of truth shared with
  `check-tools.sh`).
- Verifies required toolchain (`curl`+`bash` / `npm` / `pipx`) is on
  PATH before attempting install; prints a hint if missing.
- **`scripts/check-tools.sh` updated.** Missing tools now show the exact
  install command (delegated to `install.sh --line`); the previously
  hand-rolled hint block is gone.
- **README** install section now points at `scripts/install.sh` as the
  one-shot bootstrap; project layout updated.
- No HTTP-wrapper fallback layer was added — typed-CLI security model is
  preserved as-is. (R1 option A, not C.)

---

## v0.2.2 — 2026-04-27

Post-review correctness pass — fixes shipped in v0.2.1.

- **`references/tools.md` actor input shapes corrected** against live
  Apify input schemas (`apify actors info --input <id>`). v0.2.1 used
  guessed key names that the new community actors silently ignore:
  - `harvestapi/linkedin-profile-scraper`: `profileUrls` → `queries`
    (or `urls` / `publicIdentifiers` / `profileIds` per schema).
    Documented optional `profileScraperMode` enum for the email tier.
  - `harvestapi/linkedin-company`: `companyUrls` → `companies`
    (or `searches` for name-based lookup).
  - `apidojo/twitter-user-scraper`: `usernames` → `twitterHandles`
    (or `startUrls` / `searchTerms` / `twitterUserIds`).
  - YouTube transcript: split into two entries —
    `pintostudio/youtube-transcript-scraper` takes `videoUrl` (singular
    string) + `targetLanguage`; `topaz_sharingan/...` takes `startUrls`
    (array) + `timestamps`. The previously documented unified shape
    matched neither.
  - `viralanalyzer/telegram-channel-scraper`: `messagesLimit` →
    `maxPostsPerChannel` (capped at 500).
- **Fallback-chains table** LinkedIn row updated from
  `apify/linkedin-*` (dead) to `harvestapi/linkedin-*`.
- **Phase 7 sidecar schema:** added `schema_version: "1"` per line for
  forward-compat with the rest of the skill's JSON envelopes. Dropped
  `inferred_from[]` (dangling — no fact-ID system in the dossier
  template); re-introduce as R12.1 when a downstream consumer needs
  graph edges.
- **Phase 1 fallback wording** clarified: `WebSearch` output explicitly
  counts as a Phase-1 result for Anti-pattern #1, just lower-confidence
  than typed-CLI output. Resolves the prior "ungraded seed is still
  better than blind" tension.

---

## v0.2.1 — 2026-04-27

Trust-budget + provenance pass.

- **`references/tools.md` actor IDs verified against the live Apify Store.**
  All 8 previously TODO-flagged actor IDs resolved:
  - `apify/linkedin-profile-scraper` → `harvestapi/linkedin-profile-scraper`
  - `apify/linkedin-company-scraper` → `harvestapi/linkedin-company`
  - `apify/facebook-profile-scraper` → `cleansyntax/facebook-profile-posts-scraper`
    (low-traffic; warning kept that FB profile scraping is unreliable)
  - `pintostudio/youtube-transcript-scraper` confirmed live;
    `topaz_sharingan/Youtube-Transcript-Scraper` slug case-corrected
    (Apify slugs are case-sensitive)
  - `apidojo/twitter-user-scraper`, `apidojo/tweet-scraper` (both confirmed)
  - `web.harvester/*` and `lukaskrivka/*` Telegram slugs do not exist;
    replaced with `viralanalyzer/telegram-channel-scraper` (low-traffic
    warning attached)
- **Phase 7 sidecar (R12):** the orchestrator now emits
  `./osint-<slug>/dossier.facts.jsonl` alongside `dossier.md` — one JSON
  object per fact, schema: `{claim, grade, sources[], inferred_from[],
  notes}`. Grade-I uses `internal:{approved:"YYYY-MM-DD"}` instead of
  `sources`. Lets downstream tools verify / re-grade without re-running
  the skill.
- **Phase 1 fallback (R4 partial):** explicit instruction to use
  `WebSearch` (Brave-backed in Claude Code) when no typed search CLI is
  available, rather than starting Phase 3 blind.

---

## v0.2.0 — 2026-04-27

Coverage + portability pass.

- **Output convention changed:** dossier outputs now land under
  `./osint-<slug>/` relative to the operator's working directory at skill
  launch, **not `/tmp/osint-<slug>/`**. Frontmatter `Write(...)` allow-list
  updated; `.gitignore` extended with `osint-*/` so dev runs from inside the
  skill repo don't leak into git. Existing `/tmp/osint-*` paths are no longer
  produced.
- **New reference docs (lazy-loaded):**
  - `references/tools.md` — Apify actor catalog covering Instagram, Facebook,
    LinkedIn, TikTok, YouTube, Google Maps, X/Twitter, Telegram. Per actor:
    ID, input shape, output fields, typical cost. ~7 actor IDs marked TODO
    pending verification on the Apify Store.
  - `references/content-extraction.md` — clean-text/transcript extraction for
    YouTube, podcasts, blog/long-form, conference talks, Substack, X threads.
- **New helper scripts (`scripts/`):**
  - `first-volley.sh` — Phase 1 fan-out: one background call per available
    search CLI, 0.5 s stagger, per-job 60 s timeout, macOS-portable
    (no `tail --pid`, no `gtimeout` dependency).
  - `merge-volley.sh` — dedup by canonical URL (scheme/host lowercased,
    `utm_*` stripped, trailing slash normalised), emits unified
    `seed.json`.
  - `spend-add.sh` — appends one JSONL line per CLI call to
    `./osint-<slug>/spend.jsonl`, normalising several `cost_usd` shapes.
  - `spend-total.sh` — running total / per-provider call count, fed to the
    Phase 7 audit log.
- **New asset:** `assets/dossier-template.md` — Phase 7 output template
  extracted from inline. Placeholder syntax: `{{name}}`,
  `{{#if name}}…{{/if}}`, `{{#name}}…{{/name}}`.
- **Phase 1 rate limit:** bumped from "≤ 3 concurrent" to "≤ 4 concurrent
  (one per available search CLI)" to match the wrapper script's behaviour.
  Per-provider hammering still forbidden.
- **`ROADMAP.md`** added — R1–R15 prioritised by value × ease.

### Migration notes

- If you have previous dossiers under `/tmp/osint-<slug>/`, move them to
  `./osint-<slug>/` (relative to where you next run the skill from) — they
  will not be regenerated automatically.
- Hosts without one of the new wrapper scripts continue to work via the
  manual fallback documented in Phase 1.

---

## v0.1.0 — 2026-04-18

Initial release.

- 7-phase skill (`SKILL.md`): preflight → seed → internal intel → platform
  extraction → cross-reference → psychoprofile (optional) → gap analysis →
  dossier rendering.
- 4-gate internal-intelligence protocol (`references/phase-2-gates.md`):
  pre-execution consent → write-only execution → operator redaction →
  promotion check.
- Narrow `allowed-tools` — no `Bash(*)`, no wildcard `Write`; writes only
  to `/tmp/osint-*`.
- CLI-first orchestration: assumes `perplexity`, `exa`, `tavily`,
  `jina`, `apify`, `brightdata`, `parallel` on PATH. No inline `curl`.
- Preflight script (`scripts/check-tools.sh`): reports which CLIs and env
  vars are reachable.
- Reference docs: per-platform URL patterns + extraction chains
  (`references/platforms.md`), MBTI/Big-Five methodology
  (`references/psychoprofile.md`).

### Known limits

- `perplexity`, `exa`, `tavily` CLIs are not yet published. Skill falls
  back to Claude Code's built-in `WebSearch`/`WebFetch` when they are
  absent. Typed-CLI security story applies only when the typed CLIs are
  available.
- Fan-out / parallel-worker mode described in `DESIGN.md §3` but not
  wired in; all runs are sequential in v0.1.
- No persistence between runs by design.
