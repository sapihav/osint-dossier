# Changelog

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
