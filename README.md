# osint-dossier

> A Claude Code skill for person-focused OSINT research. From a name, handle,
> or URL, build a graded public-record dossier with confidence-scored facts,
> cited sources, and an explicit gap list. Internal signals (operator's own
> chat/email) are gated behind a 4-step human-in-the-loop protocol and never
> quoted verbatim.

Project-local install. Typed-CLI orchestrator, not a scraper. Designed with
tight `allowed-tools`, zero file-based key storage, and a fail-closed
internal-intelligence phase.

## Requirements

- Claude Code CLI (any recent version that supports skills with YAML
  frontmatter).
- At least one search provider. Skill supports:
  - `perplexity` — Perplexity API
  - `exa` — Exa AI
  - `tavily` — Tavily
  - `jina` — Jina AI (reader / search / deepsearch)
- Optional scrape providers: `apify` (Apify CLI), `brightdata`
  (@brightdata/cli).
- Keys via env vars only (see `SKILL.md §Tool layer`). The skill never
  reads key files from disk.

Preflight to see what's reachable on your host:

```bash
bash scripts/check-tools.sh
```

## Install

```bash
# Clone into your project's skills directory
mkdir -p .claude/skills
git clone https://github.com/sapihav/osint-dossier.git \
  .claude/skills/osint-dossier
```

Claude Code auto-loads the skill the next time you open the project.
Trigger it from a chat with any of: "osint `<name>`", "profile person",
"due diligence on", "dossier on `<name>`", "research person", "background
check", "досье".

## Usage

```
> Run osint-dossier on <name>. Skip internal intel. Budget $0.10.
```

The skill runs 7 phases end-to-end:

| Phase | What |
|---|---|
| 0 | Preflight: list available CLIs |
| 1 | Seed collection from external search |
| 2 | **Internal intelligence — 4-gate human-in-the-loop** |
| 3 | Platform extraction (LinkedIn, Instagram, Facebook, TikTok, YouTube, Telegram, web) |
| 4 | Cross-reference + fact grading (A/B/C/D + I for internal) |
| 5 | Psychoprofile (optional) |
| 6 | Coverage + depth scoring + gap analysis |
| 7 | Dossier rendering to `./osint-<slug>/dossier.md` (CWD-relative) |

Budget default: ≤ $0.50 per subject without asking; above that the skill
stops and prompts.

## Security posture

- **Typed-CLI only.** Skill shells out to CLIs that validate input and
  build JSON payloads via typed serialisers — no string interpolation of
  arbitrary text into shell/JSON.
- **Narrow `allowed-tools`.** No `Bash(*)`, no wildcard `Write`. Writes
  only under `./osint-*` (relative to the operator's working directory at
  skill launch).
- **Env-var-only auth.** The skill and the CLIs refuse to fall back to
  key files on disk.
- **4-gate Phase 2 protocol.** Internal-intelligence queries are written
  to a file, not inhaled into model context. Operator redacts + signs off
  with an explicit promotion line. Fail-closed: any missing gate skips
  the phase.
- **Internal data tagged as Grade I** — never counted toward
  cross-reference confirmation.

See [`DESIGN.md`](DESIGN.md) for rationale behind each decision.
See [`references/phase-2-gates.md`](references/phase-2-gates.md) for the
gate protocol in detail.

## Project layout

```
osint-dossier/
├── SKILL.md                     # The skill prompt (Claude Code loads this)
├── DESIGN.md                    # Architecture rationale
├── README.md                    # You are here
├── LICENSE                      # MIT
├── CHANGELOG.md
├── references/
│   ├── phase-2-gates.md         # 4-gate internal-intel protocol
│   ├── platforms.md             # Per-platform URL patterns and chains
│   └── psychoprofile.md         # MBTI/Big-Five methodology
└── scripts/
    └── check-tools.sh           # Preflight diagnostic
```

## Not for

- Company / product research without a named person.
- Content generation.
- Market analysis.
- Competitive intelligence.

## Contributing

Issues and PRs welcome. Before opening a PR, read `DESIGN.md` — the
security invariants in §4 are non-negotiable, even for convenience
features.

## License

MIT. See [`LICENSE`](LICENSE).
