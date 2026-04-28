# osint-dossier — Roadmap

Living doc. Items are ordered by **value × ease**. Anchored in gaps surfaced
during real runs and design review.

Date opened: 2026-04-27 · Owner: @sapihav

---

## P0 — Portability blocker

### R1. Install contract: typed CLIs from public sources ✓ done 2026-04-29
**Problem.** The skill silently assumed the host has `perplexity`, `exa`,
`tavily`, `jina`, `apify`, `brightdata` typed CLIs installed. On a fresh
machine the skill was dead — `check-tools.sh` reported red, but the operator
had nothing to actually run.

**Decision (option A, full typed-CLI):** stay typed-CLI-only. No
HTTP-wrapper fallback layer. Public sources only.

**Shipped:**
- `scripts/install.sh` — idempotent installer. `curl | bash` of each Go
  CLI's published `install.sh` (which fetches the latest GitHub release
  binary — no Go toolchain required), `npm i -g` for `apify` /
  `brightdata`, `pipx install` for `jina`. Modes: default (install
  missing), `--check`, `--line <bin>`.
- `scripts/check-tools.sh` — when a tool is missing, prints the exact
  install command by delegating to `install.sh --line`. Single source of
  truth for install commands.
- README install section updated.

---

## P1 — Coverage gaps (largest pure-feature wins)

### R2. `references/tools.md` — Apify actor catalog ✓ done 2026-04-27
**Problem.** Phase 3 says "use the right actor" but doesn't say which.

**Scope:** at minimum cover Instagram (profile, posts, comments, reels),
Facebook (pages, groups), LinkedIn (profile, company), TikTok (profile,
videos), YouTube (channel, video, transcript), Google Maps (place, reviews).
For each: actor ID, required inputs, expected output shape, typical cost.

**Effort:** M-L. **Lazy-load:** yes, only when Phase 3 hits the platform.

### R3. `references/content-extraction.md` ✓ done 2026-04-27
**Problem.** Phase 3 rule says "extract transcripts on the spot" but no how.

**Scope:** YouTube (apify actor → `yt-dlp --write-auto-sub` fallback);
podcasts (RSS + `whisper` fallback); blog/long-form (`jina read`); conference
talks (Notion/Vimeo embeds).

**Effort:** S-M. **Lazy-load:** yes.

### R4. Add Brave Search + Parallel AI as seed backends ◐ partial 2026-04-27
**Status:** Brave fallback shipped 2026-04-27 (SKILL.md Phase 1 manual
fallback path → `WebSearch`). Parallel AI still pending its typed CLI.

**Problem.** Free / cheap retrieval layer is missing. Brave is built-in to
Claude Code (no key); Parallel AI is cheap and citation-rich.

**Scope:** extend `scripts/check-tools.sh`, add to Phase 1 fan-out list,
update SKILL.md retrieval table. Brave is already partially covered via
`WebSearch` — formalise it.

**Effort:** S.

### R5. Extract dossier template to `assets/dossier-template.md` ✓ done 2026-04-27
**Problem.** Phase 7's output shape is inlined in `SKILL.md`. Editing the
template requires editing the orchestrator.

**Scope:** move to `assets/`, replace inline block with a one-line "render
via `assets/dossier-template.md`, fill placeholders". Keep grade legend +
audit-log shape in the asset.

**Effort:** S.

---

## P2 — Concrete impl of things we currently only describe

### R6. `scripts/first-volley.sh` + `scripts/merge-volley.sh` ✓ done 2026-04-27
**Problem.** Phase 1 says "3 parallel calls, 0.5 s stagger, dedup by URL +
title-similarity". Today this is the agent's responsibility — fragile,
non-deterministic.

**Scope:**
- `first-volley.sh <subject> [context...]` — spawns N background CLI calls,
  writes each to `./osint-<slug>/volley-<provider>.json`, waits with proper
  macOS-compatible timeout (no `tail --pid`).
- `merge-volley.sh <slug>` — reads all envelopes, dedups by URL +
  title-similarity, emits unified `seed.json`.

**Effort:** M.

### R7. Cost & elapsed accounting harness ✓ done 2026-04-27
**Problem.** Skill says "tracked from CLI output" but there's no aggregator.
Operator has no running total mid-session.

**Scope:**
- `scripts/spend-add.sh <envelope.json> <slug>` — appends one JSONL line per
  call to `./osint-<slug>/spend.jsonl`.
- `scripts/spend-total.sh <slug>` — returns running `{total_usd, calls}` JSON.
- Phase 7 audit log reads from this.

**Effort:** S.

---

## P3 — Things to consider, not yet committed

### R8. Default-on parallel collection?
Today fan-out is opt-in. Re-evaluate after R2 lands — with a real actor
catalog, parallelism becomes more obviously valuable. Trade-off: speed vs
token cost vs context-isolation safety.

### R9. Caching of identical queries within a session
Right now if two phases ask the same thing, we pay twice. Add hash-keyed
cache under `./osint-<slug>/.cache/`.

### R10. Output formats beyond markdown
HTML / PDF / JSON-export of the dossier for downstream consumers. YAGNI
unless an actual consumer asks.

### R11. Subject-graph (entity links)
Currently flat fact list. Could emit a sidecar JSON of entities (people,
orgs, places) with relations. Useful for downstream graph tools. Not a
priority until a consumer exists.

### R12. Sidecar `dossier.facts.jsonl` (provenance graph) ✓ done 2026-04-27
One fact per line: `{schema_version, claim, grade, sources[], notes}`,
or `{...grade:"I", internal:{approved}}` for operator-approved internal
facts. Lets downstream tools verify or re-grade without re-running the
skill. Cheap addition, big payoff for tooling. No prior art seen.

**Follow-up R12.1 (open):** add per-fact `id` rendering in
`assets/dossier-template.md` so the sidecar can reference cross-fact
provenance via `inferred_from: [<fact-id>]`. Dropped from initial v0.2.1
shipment as YAGNI — re-open when an actual consumer wants graph edges.

### R13. Per-phase YAML I/O contracts
Today phases are described in prose. A short YAML schema per phase
(`inputs`, `outputs`, `side_effects`, `gates`) would make the contract
machine-checkable and refactor-safe.

### R14. Test corpus of canned subjects
1 dead public figure, 1 corporate exec, 1 micro-celebrity, 1
namesake-collision case — with snapshot dossiers for regression testing.

---

## P0 (operator-driven additions)

### R15. Output convention — PWD-relative, not `/tmp` ✓ done 2026-04-27
**Status:** done 2026-04-27.

Operator requirement: dossier outputs must land in the operator's working
directory at skill launch (`./osint-<slug>/`), not `/tmp/osint-<slug>/`.

**Scope:**
- Update `SKILL.md` paths throughout (Phases 0, 1, 2, 3, 7, security posture).
- Update frontmatter `Write(...)` allow-list to permit `./osint-*/**`.
- Add `osint-*/` to `.gitignore` so dev runs from inside the skill repo
  don't leak into git.
- Update `references/phase-2-gates.md` if it cites the old path.

---

## Out of scope (explicitly)

- Live monitoring / alerts on a subject — different product.
- Active-investigation tools (e.g., contacting subjects, sending messages).
- Auto-renewal of dossiers on a schedule — see "loop" / "schedule" skills.
- Bypass of authwalls / CAPTCHAs without explicit operator authorisation —
  legal/ethical guardrail, not a roadmap item.

---

## How to work this list

1. One PR = one R-item. ≤ 500 lines of skill code per PR.
2. Each R-item must update `CHANGELOG.md` and tick the box here.
3. If a P0/P1 item turns out to break the rigor invariants
   (4-gate Phase 2, typed-CLI security boundary, etc.) — stop and re-design
   before merging.
