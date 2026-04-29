# osint-dossier

> A Claude Code skill for person-focused OSINT research. From a name, handle,
> or URL, build a graded public-record dossier with confidence-scored facts,
> cited sources, and an explicit gap list. Internal signals (operator's own
> chat/email) are gated behind a 4-step human-in-the-loop protocol and never
> quoted verbatim.

Project-local install. Typed-CLI orchestrator, not a scraper. Designed with
tight `allowed-tools`, zero file-based key storage, and a fail-closed
internal-intelligence phase.

## Prerequisites

The host must have the following **before** running `scripts/install.sh`:

| Requirement | Why | Install hint |
|---|---|---|
| macOS or Linux | Bash scripts assume POSIX + Darwin/Linux; Windows not tested | — |
| Claude Code CLI | Loads and runs the skill | https://claude.com/claude-code |
| `bash` ≥ 4 + `curl` | Used to fetch each Go CLI's release binary | preinstalled on macOS / most Linux |
| `node` + `npm` | `apify` and `brightdata` are npm packages | `brew install node` / `apt install nodejs npm` |
| `pipx` | `jina` is a Python package | `brew install pipx && pipx ensurepath` |
| `jq` | Used by the orchestrator scripts and by each Go CLI installer to read GitHub releases | `brew install jq` / `apt install jq` |
| Provider API keys exported as env vars | Skill never reads key files from disk; CLIs refuse on-disk fallback | see **Dependencies** below |

Run preflight at any time to see what's missing:

```bash
bash scripts/check-tools.sh
```

## Dependencies

These are the CLIs the skill calls at runtime. `scripts/install.sh`
installs all of them from public sources only — no Go toolchain
required, no local repos referenced.

```bash
bash scripts/install.sh
```

| CLI | Purpose | Required env var | Install method |
|---|---|---|---|
| `perplexity` | Search / retrieval | `PERPLEXITY_API_KEY` | `curl \| bash` from [`sapihav/perplexity-cli`](https://github.com/sapihav/perplexity-cli) release |
| `exa` | Search / retrieval | `EXA_API_KEY` | `curl \| bash` from [`sapihav/exa-cli`](https://github.com/sapihav/exa-cli) release |
| `tavily` | Search / retrieval | `TAVILY_API_KEY` | `curl \| bash` from [`sapihav/tavily-cli`](https://github.com/sapihav/tavily-cli) release |
| `parallel-cli` | Search / retrieval / deep research | `PARALLEL_API_KEY` | `curl \| bash` from [parallel-web/parallel-web-tools](https://github.com/parallel-web/parallel-web-tools) release |
| `jina` | Reader / search / deepsearch | `JINA_API_KEY` | `pipx install jina` |
| `apify` | Platform scraping (LinkedIn / IG / FB / TikTok / YouTube / Telegram / Maps) | `APIFY_TOKEN` | `npm install -g apify-cli` |
| `brightdata` | Authwalled platform scraping fallback | `BRIGHTDATA_API_KEY` | `npm install -g @brightdata/cli` |

**At least one search provider** (perplexity / exa / tavily / parallel-cli / jina) is
required for Phase 1; the skill fails preflight otherwise. Scrape
providers are optional — Phase 3 degrades gracefully if neither is on
PATH.

The installer is idempotent in the "skip already-present" sense — re-running
it skips tools already on `$PATH`. It does **not** detect or upgrade stale
versions; to upgrade, uninstall the binary first and re-run, or use the
tool's native upgrade command. To see the install command for a single
tool without running it: `bash scripts/install.sh --line <bin>`.

## Install the skill

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
├── ROADMAP.md                   # R1–R15 prioritised
├── LICENSE                      # MIT
├── CHANGELOG.md
├── assets/
│   └── dossier-template.md      # Phase 7 fillable template
├── references/
│   ├── phase-2-gates.md         # 4-gate internal-intel protocol
│   ├── platforms.md             # Per-platform URL patterns and chains
│   ├── tools.md                 # Apify actor catalog
│   ├── content-extraction.md    # YouTube/podcast/blog/talk transcripts
│   └── psychoprofile.md         # MBTI/Big-Five methodology
├── scripts/
│   ├── install.sh               # Install all expected CLIs (public sources)
│   ├── check-tools.sh           # Preflight diagnostic
│   ├── first-volley.sh          # Phase 1 parallel fan-out
│   ├── merge-volley.sh          # Phase 1 dedup + seed.json merge
│   ├── spend-add.sh             # Append CLI call to spend.jsonl
│   └── spend-total.sh           # Running cost rollup
└── samples/
    └── jony-ive-2026-04-26/     # Baseline dossier for post-port compare
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
