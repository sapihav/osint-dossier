# osint-dossier — Design Notes

Non-obvious architectural decisions. Written so anyone who picks this up six
months from now understands *why* it's shaped the way it is, not just *what*
it does.

---

## 1. CLI-first, not curl-in-a-shell

The skill shells out to typed CLIs (`perplexity`, `exa`, `jina`, …) rather
than to inline `curl` commands that interpolate arguments.

**Why.** Inline `curl` with user-controlled strings is the single most common
source of shell/JSON injection bugs in LLM-orchestrated tools. Every reference
OSINT skill-repo I reviewed had at least one injection path of that shape. A
typed CLI parses arguments into typed variables; there is no string
concatenation into the wire-protocol message, and there is no path for a
scraped piece of text to become an executed command. The correctness story is
*structural*, not a "please be careful" rule.

**Consequence.** The skill cannot run against providers for which there is no
CLI yet. We accept that trade-off: better "fails with a clear install hint"
than "runs with an unsafe curl fallback".

**Pointer.** Which CLIs exist / are planned / are official: see
`~/src/CLI-tools-ROADMAP.md`.

---

## 2. Four-gate internal-intelligence protocol

The internal-intelligence phase (Phase 2) — searching the operator's own
Telegram / email / vault for the subject — is behind four explicit gates:

1. Pre-execution consent (`AskUserQuestion` "proceed?").
2. Raw results go **to a file**, not into the model's context.
3. Operator redaction window + explicit `PROMOTION: APPROVED …` line.
4. Promotion-file integrity check before any downstream phase reads it.

**Why four, not one.** A single consent prompt gives you a binary switch.
Four gates give you failure modes that are *recoverable*:

- Gate 1 fail → no queries ran, no local state changed.
- Gate 2 is structural (the model literally doesn't see the raw content),
  so a subsequent model slip cannot leak what the model was never shown.
- Gate 3 is the value-add: the operator decides *per finding* what to keep,
  redact, paraphrase, or drop.
- Gate 4 is the "can I be sure you approved this?" mechanical check —
  guarding against the model itself trying to promote a file that wasn't
  signed off (e.g. after a prompt-injection in Phase 1).

**Alternative considered: one consent prompt + "please don't quote DMs".**
Rejected because "don't quote" is a soft instruction to the model; soft
instructions fail in the tail of the distribution. The four-gate design
moves enforcement out of the prompt and into the file-system protocol: the
agent *cannot* see internal text until the operator writes a specific marker
line into a specific file.

**Grade "I" for internal findings.** Internal data is tagged with a separate
grade `I`. It is explicitly **not** counted toward the A-grade cross-reference
rule. This prevents an accidental "LinkedIn says X + internal chat says X ⇒
Grade A" double-counting.

---

## 3. Fan-out (parallel workers) is off by default

Running Phase 3 as a fan-out of 3–5 Sonnet sub-agents is offered as an opt-in
mode, not the default.

**Why.** Parallelism looks attractive (≈ 5× wall-clock speedup for big-
footprint subjects) but has three hidden costs:

1. **Context amplification.** Without care, every sub-agent inherits the
   main agent's context including Phase-2 content. That re-sends sensitive
   data to N separate model calls and N separate Anthropic API requests.
   The mitigation ("only pass the minimum") is prompt-shaped and easy to
   violate; keeping fan-out off by default removes the temptation.
2. **Rate-limit stacking.** 5 workers all calling Apify / Jina / Perplexity
   concurrently can trip per-account rate limits much faster than one
   worker spacing calls.
3. **Cost surprise.** Each Sonnet worker has its own turn budget. A 5-worker
   run at $0.10 each is $0.50 before any Phase 4–6 work. Default-on makes
   that easy to forget.

**When to turn it on.** Operator explicitly asks, subject has an outsized
public footprint (high-profile founder, active influencer), budget is
pre-authorised. Turning it on should be a conscious decision, not the
default path.

**Hard rule when on.** Sub-agents get subject name + handle + 1-2 context
keywords. **Not** the Phase 2 content. Never.

---

## 4. Project-local install, not global

Installed at `./.claude/skills/osint-dossier/`, inside the project that uses
it. Not at `~/.claude/skills/osint-dossier/`.

**Why.** Global install would make every Claude Code project on this
machine aware of (and able to auto-invoke) this skill. The attack surface
grows: a prompt-injection in an unrelated project could trigger OSINT
queries. Project-local install scopes the blast radius to the project where
the operator is deliberately doing OSINT work.

**Trade-off accepted.** A project-local skill is not discoverable from
other projects. When setting up a new project that needs it, copy or
symlink the folder explicitly.

---

## 5. Narrow `allowed-tools` from day 1

The frontmatter restricts the skill to a small, specific list: the CLI
binaries it uses, `WebSearch`/`WebFetch` for fallbacks, `Read`/`Glob`/`Grep`
for phase-2 vault searches, `Write` **only** under `./osint-*` (CWD-relative), and
`AskUserQuestion` for gates.

**Why.** If the skill is ever loaded from a position where the session also
has `Bash(*)` enabled, an attacker-controlled payload inside a scraped page
could otherwise trick the agent into running arbitrary commands. `Bash(*)`
is never in the skill's allow list; only `Bash(<binary>:*)` for the six
trusted external CLIs and the skill's own helper scripts (each listed by
explicit path).

**Alternative considered.** `Bash(.claude/skills/osint-dossier/scripts/*.sh:*)`
for generic script loading — rejected because scripts in that folder could
be expanded later without the allow-list updating. Better to list each
binary path explicitly.

---

## 6. No file-based key fallbacks

The skill documents that keys come from **env vars**. It does not read
`$HOME/.config/<provider>/key.txt`-style fallbacks, and it tells the
underlying CLIs not to either (`--no-file-fallback` flag — part of the
CLI spec in the roadmap).

**Why.** File-based key fallbacks are the easiest way to leak keys across
skills / tools / crash logs / git mishaps. Env vars at least stay in the
shell's env scope and are not serialised to disk by default.

---

## 7. What this skill doesn't do, on purpose

- **No tabular dossier.** Final dossier uses bullet lists, not markdown
  tables. Many downstream clipboards / chat clients mangle tables.
- **No psychoprofile by default.** Only when the operator explicitly
  requests. MBTI-from-text is inferential; forcing it into every run
  over-claims.
- **No "Grade A" without 2 cross-refs.** A single source, no matter how
  credible, is at best Grade B.
- **No zodiac / family / DOB inference.** Unless sourced at Grade A or B.
- **No auto-disambiguation on a common name.** Operator picks.
- **No Telegram DMs in outputs, ever** — paraphrase only, cited as
  internal.

These are design decisions, not TODOs.

---

## 8. Origin of design decisions

This skill was written from scratch. Sources informing the design:

- Bellingcat / OSINT-community public methodology.
- Public provider documentation (Perplexity, Exa, Tavily, Jina, Apify,
  Bright Data, Parallel AI).
- Author's prior work with LLM-orchestrated tool chains — specifically
  the lessons from building a sibling skill (`/public-voice`, a
  person-tracking tool that queries public appearances).
- OSINT community conventions for phase structure (preflight → seed →
  platform extraction → cross-reference → synthesis) and for
  confidence grading (A/B/C/D).

No third-party OSINT skill code or prompt text was copied. Concepts that
share names with community conventions (e.g., "Phase 0 preflight",
"Grade A/B/C/D") are independently derived.
