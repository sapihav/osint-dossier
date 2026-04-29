# osint-dossier — Roadmap

Living doc. Items are ordered by **value × ease**, anchored against a
parity reference: an external OSINT skill we surveyed for feature scope,
plus gaps surfaced during real runs and design review.

Date opened: 2026-04-27 · Last revised: 2026-04-29 · Owner: @sapihav

---

## Deliberate divergences (NOT gaps to close)

Areas where we ship something different from the parity reference on
purpose. Do not re-open without re-litigating the security / design
trade-off.

1. **No HTTP-wrapper layer.** Typed CLIs are the security boundary;
   `install.sh` installs them from public sources. The reference skill
   ships per-provider bash wrappers that hit raw HTTP — we deliberately
   chose typed-CLI only (R1 option A).
2. **Phase 2 is human-gated and fail-closed.** Internal-intelligence
   content (Telegram DMs, email bodies, vault contacts) is never
   inhaled into model context. The reference skill's equivalent phase
   does inhale and treats internal data as Grade A. We tag internal
   facts as Grade I and require a 4-gate operator promotion. This is
   the core distinguishing posture of this skill.

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
- `scripts/install.sh` — installer. `curl | bash` of each Go CLI's
  published `install.sh` (which fetches the latest GitHub release
  binary — no Go toolchain required), `npm i -g` for `apify` /
  `brightdata`, `pipx install` for `jina`. Modes: default (install
  missing), `--check`, `--line <bin>`. Idempotent in the
  "skip-already-present" sense; does not auto-upgrade.
- `scripts/check-tools.sh` — when a tool is missing, prints the exact
  install command by delegating to `install.sh --line`.
- README split into Prerequisites + Dependencies sections.

### R15. Output convention — PWD-relative, not `/tmp` ✓ done 2026-04-27
Operator requirement: dossier outputs must land in the operator's working
directory at skill launch (`./osint-<slug>/`), not `/tmp/osint-<slug>/`.

---

## P1 — Parity gaps that actually move the needle

### R8. Swarm Mode default — concrete sub-agent spawn protocol [PROMOTED 2026-04-29]
**Problem.** Today fan-out at the agent level is opt-in and described in
prose. The reference skill makes parallel sub-agent collection the
DEFAULT and specifies a concrete spawn protocol; we don't.

**Scope:**
- Promote sub-agent fan-out to the default Phase-3 path (sequential
  remains as `--seq` opt-out).
- Document concrete task-split buckets in SKILL.md — five slots
  covering: video/transcript, authwalled-deep (FB / LinkedIn),
  open-graph social (IG / X / Telegram), regional + maps + registries,
  deep-research (Perplexity / Exa / Parallel deep modes).
- Each sub-agent gets ALL known data from Phase 1 seed, writes results
  to `./osint-<slug>/swarm-<task>.md`, runs on a cheaper model.
- Per-agent budget cap ≤ $0.15; total swarm cap ≤ $0.50.
- Main agent waits for all sub-agents before Phase 4 cross-reference.
- Phase 2 (internal intel) **stays in main agent only** — never
  delegated to a sub-agent. Non-negotiable per security invariant.

**Effort:** L. Touches SKILL.md substantially. ≤500 LOC achievable
because the sub-agent spawn primitive lives in the host agent runtime.

### R16. Universal Apify actor runner [NEW 2026-04-29]
**Problem.** Today Phase 3 calls `apify` CLI directly and the operator /
agent has to know each actor's input shape. The v0.2.1 → v0.2.2 patch
cycle (correcting `profileUrls` → `queries`, `usernames` → `twitterHandles`,
etc.) is exactly the failure mode this prevents. The reference skill ships
a single `run-actor.sh <actor_id> <json_input>` entry point that handles
auth, version, and output formatting uniformly.

**Scope:**
- `scripts/run-actor.sh <actor_id> <json_input> [--output <path>] [--format csv|json]`.
- Implementation in Node (`scripts/run_actor.js`) using the Apify SDK —
  bash wrapper for env loading + arg shaping.
- Output normalised to the same JSON envelope as the typed CLIs
  (`schema_version`, `result`, `cost_usd`, `elapsed_ms`).
- `references/tools.md` rewrites: per actor we now only need
  `actor_id` + `input_shape_example` — runner does the call, so the
  catalog is documentation, not orchestration glue.
- `package.json` added under `scripts/` for the runner's deps.

**Effort:** M-L. Adds Node prerequisite (already listed under npm CLIs,
but a runner is heavier than a one-shot install).

### R18. Research Escalation Flow — formalised cost/depth tiers [NEW 2026-04-29]
**Problem.** SKILL.md mentions "use cheap before expensive" in passing
but doesn't formalise it. The reference skill has explicit Levels 1–4
(seconds/$0 → minutes/$0.50) with provider mappings per level. Without
this, the agent picks providers ad-hoc and budget overruns are common.

**Scope:**
- New section in SKILL.md: "Research Escalation Flow" with four levels.
  - L1 (seconds, ~$0): web search + Perplexity Sonar + Exa search +
    Tavily basic — fan out, take whatever's cheapest first.
  - L2 (seconds-minutes, ~$0.01): source verification via `jina read` /
    Tavily extract on top hits.
  - L3 (minutes, ~$0.05–0.10): Apify actors for platform extraction
    when an open-graph profile is in scope.
  - L4 (minutes, ~$0.25–0.50): deep research modes — Perplexity Deep,
    Exa Deep, Parallel Deep — only after L1–L3 fail to close gaps.
- Decision rule per level: "ascend only if Phase 6 gap analysis flags
  unfilled high-priority slots".
- Phase 7 audit log records which level each fact was sourced from.

**Effort:** S-M. Mostly SKILL.md prose + a small section in
`assets/dossier-template.md` audit-log block.

### R2.1. Expand Apify actor catalog to reference breadth [NEW 2026-04-29]
**Problem.** R2 shipped a catalog covering ~10 platform/actor combos.
The reference skill claims 55+ actors embedded — broader coverage of
secondary actors per platform (e.g. comments scrapers, tagged-posts
scrapers, contact-info enrichers) and additional platforms.

**Scope:**
- Add to `references/tools.md`: comments / tagged / hashtag scrapers
  per platform; contact-info enrichers (`vdrmota/contact-info-scraper`
  etc.); regional registries; Yandex/DuckDuckGo search variants.
- Each entry verified against `apify actors info --input <id>` per the
  v0.2.2 lesson — input shapes are not guessable.
- Trade-off: bigger catalog = more lazy-load weight when Phase 3 reads
  the file. Mitigate by adding `references/tools-extras.md` with the
  long tail, keeping `tools.md` focused on the top-tier actors.

**Effort:** M. Mostly cataloguing + verification; pairs naturally with
R16 (runner makes the catalog purely informational).

### R4. Brave Search + Parallel AI as seed backends ✓ done 2026-04-29
**Shipped:**
- Brave: `WebSearch` fallback (Phase 1) — done 2026-04-27.
- Parallel AI: Parallel published `parallel-cli` via
  [parallel-web/parallel-web-tools](https://github.com/parallel-web/parallel-web-tools).
  Wired into `install.sh` (`curl -sSL https://parallel.ai/install.sh
  | bash`), `check-tools.sh`, README Dependencies, and SKILL.md
  frontmatter allow-list (binary renamed `parallel` → `parallel-cli`
  to match upstream and avoid collision with GNU parallel).

### R19. Stage-by-stage artifact persistence [NEW 2026-04-29]
**Problem.** Today only some phase outputs land on disk
(`seed.json` from Phase 1 via R6, `dossier.md` + `dossier.facts.jsonl`
from Phase 7 via R12, `spend.jsonl` via R7). Phases 3, 4, 5, 6
produce data that flows phase-to-phase in the agent's context but is
never persisted. If a run is interrupted, sub-agents fan out, or the
operator wants to audit what each stage produced, the data is gone.

**Operator requirement:** every stage's output must land on disk so
that any phase can be re-run from the prior stage's artifact without
redoing earlier work.

**Scope:**
- All phase outputs land under `./osint-<slug>/stages/` with a
  consistent naming convention:
  - `00-tooling.json` — Phase 0 preflight result (CLIs available, env
    vars set, has_search bool).
  - `01-seed.json` — Phase 1 merged search results (already exists;
    move under `stages/` or symlink for back-compat).
  - `02-internal.gates.log` — Phase 2 4-gate audit trail (NOT the
    content; just gate state). Already file-based per the gate
    protocol.
  - `03-platform-<platform>.json` — Phase 3 per-platform extraction
    output (one file per platform: linkedin, instagram, facebook,
    tiktok, youtube, telegram, web).
  - `04-cross-ref.json` — Phase 4 graded fact list pre-render (the
    same shape as `dossier.facts.jsonl` plus working notes).
  - `05-psychoprofile.json` — Phase 5 raw structured output (only if
    psychoprofile ran).
  - `06-gaps.json` — Phase 6 gap analysis output.
  - `07-dossier.md` + `07-dossier.facts.jsonl` — Phase 7 (already
    exist at the top level; mirror or move).
- All writes atomic (write to `*.tmp` then `mv`).
- Phase N reads its input from `stages/0(N-1)-*.json`, not from
  conversation context — makes phase-resumability real.
- SKILL.md updated to instruct the agent to write each stage's
  artifact before proceeding.
- `assets/dossier-template.md` audit log gains a one-line stage
  manifest pointing at the artifacts.

**Why P1 / why first:**
Foundational for R8 (sub-agents must write per-stage), R16 (actor
runner output is a stage artifact), and R18 (escalation flow decides
"ascend?" by reading the prior stage's gaps file). Implementing R19
first means R8/R16/R18 can be built on top instead of retrofitted.

**Effort:** M. Mostly SKILL.md prose + a small helper for
atomic-write-and-checkpoint, optional.

**Not in scope:** content snapshots of internal-intel data (Phase 2
content stays out of disk per the 4-gate protocol; only the gate
audit log is persisted).

---

## P2 — Real but lower priority

### R17. MCP client for non-typed-CLI services [NEW 2026-04-29]
**Problem.** Some retrieval / scrape services expose only an MCP
endpoint (e.g. Bright Data's MCP server, future MCP-only providers).
Today we have no path to call them — they fall outside the typed-CLI
boundary. The reference skill ships a small Python MCP client
(Streamable HTTP / SSE) for exactly this case.

**Scope:**
- `scripts/mcp-client.py` — JSON-RPC over Streamable HTTP/SSE, list
  tools + call tool. No external deps (stdlib only).
- Same JSON envelope as typed CLIs.
- SKILL.md addition: when a typed CLI exists for a service, prefer it;
  use the MCP client only when no typed CLI is available.
- Auth via env var (`<SERVICE>_MCP_URL` containing the token in the URL,
  or a separate `<SERVICE>_MCP_TOKEN` — TBD).

**Why P2, not P1:** contingent on us actually wanting MCP-only
services. Bright Data's typed CLI exists (`brightdata`); the MCP path
is mostly useful for newer providers we haven't onboarded. Re-rank to
P1 if a target service appears that has no CLI.

**Effort:** S-M.

### R9. Caching of identical queries within a session
Right now if two phases ask the same thing, we pay twice. Add hash-keyed
cache under `./osint-<slug>/.cache/`. Worth doing once Swarm Mode (R8)
lands — the duplicate-query rate goes up when sub-agents work in
parallel.

**Effort:** S.

---

## P3 — Defer / reconsider

### R13. Per-phase YAML I/O contracts
A short YAML schema per phase (`inputs`, `outputs`, `side_effects`,
`gates`) would make the contract machine-checkable and refactor-safe.
Significant SKILL.md rework. Defer until R8 + R16 + R18 stabilise the
phase shape.

### R12.1. Per-fact `id` rendering (gated on consumer)
Sidecar `dossier.facts.jsonl` (R12) shipped without per-fact IDs. Add
when a downstream consumer wants graph edges (`inferred_from: [<id>]`).

### R11. Subject-graph (entity links) — gated on consumer
Currently flat fact list. Could emit a sidecar JSON of entities with
relations. Not a priority until a consumer exists.

### R10. Output formats beyond markdown — YAGNI
HTML / PDF / JSON-export of the dossier. YAGNI unless an actual
consumer asks.

---

## Killed / superseded

### R14. Test corpus of canned subjects ✗ killed 2026-04-29
**Original idea:** 1 dead public figure, 1 corporate exec, 1
micro-celebrity, 1 namesake-collision case — with snapshot dossiers
for regression testing.

**Why killed:** R14 is regression protection for graded/scored
algorithms. This skill is mostly prose in SKILL.md and reference docs;
the only "algorithmic" surface is Phase 4 grading + Phase 6 coverage
scoring, which don't change often. Re-open if R8 / R16 / R18 introduce
non-trivial logic that warrants regression coverage.

---

## Already shipped (P1/P2 done items)

- **R2** ✓ done 2026-04-27 — `references/tools.md` Apify actor catalog (initial breadth; expand under R2.1).
- **R3** ✓ done 2026-04-27 — `references/content-extraction.md`.
- **R5** ✓ done 2026-04-27 — Dossier template extracted to `assets/dossier-template.md`.
- **R6** ✓ done 2026-04-27 — `scripts/first-volley.sh` + `scripts/merge-volley.sh` (Phase 1 fan-out).
- **R7** ✓ done 2026-04-27 — Cost & elapsed accounting (`spend-add.sh` / `spend-total.sh`).
- **R12** ✓ done 2026-04-27 — Sidecar `dossier.facts.jsonl` (provenance graph).

---

## Out of scope (explicitly)

- Live monitoring / alerts on a subject — different product.
- Active-investigation tools (e.g., contacting subjects, sending messages).
- Auto-renewal of dossiers on a schedule — see "loop" / "schedule" skills.
- Bypass of authwalls / CAPTCHAs without explicit operator authorisation —
  legal/ethical guardrail, not a roadmap item.
- HTTP-wrapper fallback layer — see Deliberate divergences.
- Pulling internal-intel content into model context — see Deliberate divergences.

---

## How to work this list

1. One PR = one R-item. ≤ 500 lines of skill code per PR.
2. Each R-item must update `CHANGELOG.md` and tick the box here.
3. If a P0/P1 item turns out to break the rigor invariants
   (4-gate Phase 2, typed-CLI security boundary, etc.) — stop and re-design
   before merging.
4. Parity check: after every shipped P1 item, re-audit against the
   parity reference. Promote / kill / add R-items as needed.
