# osint-dossier — Roadmap

Living doc. Items are ordered by **value × ease**, anchored against a
parity reference: an external OSINT skill we surveyed for feature scope,
plus gaps surfaced during real runs and design review.

Date opened: 2026-04-27 · Last revised: 2026-04-29 (R19) · Owner: @sapihav

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

### R18. Research Escalation Flow — small SKILL.md table [NEW 2026-04-29, scoped down]
**Problem.** SKILL.md mentions "use cheap before expensive" in passing
but doesn't formalise it.

**Scope (intentionally small):**
- Add a 4-row table in SKILL.md mapping providers to cost tiers:
  - L1 (~$0): `WebSearch`, Perplexity Sonar, Exa search, Tavily basic.
  - L2 (~$0.01): `jina read`, Tavily extract.
  - L3 (~$0.05–0.10): `apify call <id>` for platform extraction.
  - L4 (~$0.25–0.50): Perplexity Deep / Exa Deep / Parallel Deep.
- One rule: "ascend only when Phase 6 flags unfilled high-priority
  slots".

That's it — no new section heading hierarchy, no per-level decision
trees, no audit-log changes. Goal is to make the existing prose rule
concrete, not to introduce new ceremony.

**Effort:** S. Pure SKILL.md prose, ≤30 lines added.

### R4. Brave Search + Parallel AI as seed backends ✓ done 2026-04-29
**Shipped:**
- Brave: `WebSearch` fallback (Phase 1) — done 2026-04-27.
- Parallel AI: Parallel published `parallel-cli` via
  [parallel-web/parallel-web-tools](https://github.com/parallel-web/parallel-web-tools).
  Wired into `install.sh` (`curl -sSL https://parallel.ai/install.sh
  | bash`), `check-tools.sh`, README Dependencies, and SKILL.md
  frontmatter allow-list (binary renamed `parallel` → `parallel-cli`
  to match upstream and avoid collision with GNU parallel).

### R19. Stage-by-stage artifact persistence ✓ done 2026-04-29
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

### R8. Opt-in sub-agent fan-out for Phase 3 [DEMOTED + RESCOPED 2026-04-29]
**Was:** "Swarm Mode default" — promote fan-out to default Phase-3 path.
**Now:** opt-in only. Operator triggers via explicit request (e.g.
`--swarm`); sequential remains the default.

**Rationale for the rescope.** No wall-clock SLA driving us; Phase-1
parallelism already exists at the shell level (`first-volley.sh`); the
only place sub-agents help meaningfully is Phase-3 per-platform
prompt-shaping; and "default-on swarm" is a footgun against the
Phase-2 security invariant (sub-agents must not touch internal intel).

**Scope when invoked:**
- Up to 5 sub-agents, each scoped to one platform cluster (video /
  authwalled-deep / open-graph-social / regional+maps / deep-research).
- Each sub-agent reads from `stages/01-seed.json` (R19) and writes to
  `stages/03-platform-<task>.json` (R19). No conversation-context
  hand-off.
- Per-agent budget cap ≤ $0.15; total ≤ $0.50.
- Phase 2 (internal intel) is **never** delegated to a sub-agent.

**Effort:** M. Concrete protocol + opt-in flag in SKILL.md. Builds on
R19 (stage outputs are the IPC).

### R2.1. Apify actor catalog — methodology rule + on-demand growth [DEMOTED 2026-04-29]
**Was:** "Expand to reference breadth (~55 actors)".
**Now:** kill the breadth target. The valuable bit is the methodology;
catalog grows on-demand when Phase 3 actually needs an actor we
haven't documented yet.

**Methodology rule (permanent, not a one-time sprint):** every
`references/tools.md` entry MUST be verified against
`apify actors info <id> --input --json` before landing. The Apify
input schema is the authority; guessed shapes silently produce empty
results (the v0.2.1 lesson). Document the actual shape, not what
looks reasonable.

**Phase 3 invocation pattern (no wrapper needed):**
`apify call <id> --input '<json>' --json --silent`.

**Effort:** S per actor added; permanent rule.

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
scoring, which don't change often. Re-open if R8 / R18 introduce
non-trivial logic that warrants regression coverage.

### R16. Universal Apify actor runner ✗ killed 2026-04-29
**Original idea:** ship `scripts/run-actor.sh` + `scripts/run_actor.js`
as a uniform entry point for any Apify actor.

**Why killed:** the typed `apify` CLI already provides every capability
a runner would — `apify call <id> --input '{...}' --json` for any
actor, `apify actors info <id> --input --json` to fetch the input
schema, plus `--silent` / `-m` / `-t` knobs. The reference skill
ships a Node runner because it uses HTTP-wrapper shells everywhere
and wants envelope uniformity across them; that constraint doesn't
apply to us (we use typed CLIs uniformly). The "input shape drift"
problem (v0.2.1 → v0.2.2 patch cycle) isn't fixed by a runner either —
that's a methodology problem, folded into R2.1.

### R17. MCP client for non-typed-CLI services ✗ killed 2026-04-29
**Original idea:** lightweight Python MCP client (Streamable HTTP/SSE)
for services that expose only an MCP endpoint.

**Why killed:** YAGNI. No concrete MCP-only target service. Bright
Data has a typed CLI; future MCP-only providers are speculative. The
reference skill has it because they wanted to call Bright Data via
MCP for some operations; for us, the typed CLI is sufficient. Re-open
if and when a target service appears that has no CLI path.

### R9. Caching of identical queries within a session ✗ killed 2026-04-29
**Original idea:** hash-keyed cache under `./osint-<slug>/.cache/`
to avoid paying twice for the same query.

**Why killed:** YAGNI. No measured duplicate-query rate; the phase
sequence is linear so within-run repeats should be rare. Classic
over-engineering bait. Re-open if telemetry from real runs shows a
non-trivial duplicate rate.

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
