# Changelog

## v0.2.1 — 2026-04-27

Trust-budget + provenance pass.

- **`references/tools.md` actor IDs verified against the live Apify Store.**
  All 8 previously TODO-flagged actor IDs resolved:
  - `apify/linkedin-profile-scraper` → `harvestapi/linkedin-profile-scraper`
  - `apify/linkedin-company-scraper` → `harvestapi/linkedin-company`
  - `apify/facebook-profile-scraper` → `cleansyntax/facebook-profile-posts-scraper`
    (low-traffic; warning kept that FB profile scraping is unreliable)
  - `pintostudio/youtube-transcript-scraper`, `topaz_sharingan/Youtube-Transcript-Scraper`
    (the latter slug is case-sensitive; corrected)
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
