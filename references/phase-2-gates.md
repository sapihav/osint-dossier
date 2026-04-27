# Phase 2 — The Four Gates in Detail

Internal-intelligence phase, fully specified. Read `SKILL.md` §"Phase 2" first
for the summary. This file adds edge cases and failure-mode handling.

---

## Why gates at all

Phase 2 touches three categories of data that external search never touches:

- **Operator's own Telegram DMs with the subject.**
- **Operator's own email to/from the subject.**
- **Operator's vault / CRM notes about the subject.**

These are almost always richer than anything on LinkedIn for a warm contact
— which is exactly why naïve use is dangerous. The risks:

- **Provider exfiltration.** Anything pulled into the model's context is sent
  to the Anthropic API. Your private DMs become part of an API request.
- **Chain-injection.** If a DM contains a prompt-injection payload (e.g. the
  counterparty once pasted a suspicious link) and it's inhaled as context,
  every subsequent tool call carries that payload. The typed-CLI layer
  protects against arbitrary commands, but not against the agent
  summarising-with-bias.
- **Downstream leakage.** The dossier is produced to be shared. A verbatim
  DM quote in a shared dossier is a privacy breach of the counterparty,
  not just the operator.

The gates move enforcement out of the prompt (soft) into the file system
(hard).

---

## Gate 1 — Pre-execution consent

### Question text (verbatim)

> *"About to query local sources for subject `<name>`. I will search
> Telegram history (if available), email inbox (if available), and
> `vault/crm/*.md` (if that folder exists). Results will go to a file for
> your review. Nothing is pulled into the dossier without your explicit
> approval. Proceed?"*

### Options

- `yes — proceed` → Gate 2.
- `skip internal — go to Phase 3` → skip Phase 2 entirely, move to platform
  extraction.
- `cancel` → abort the whole skill; report state so far.

### Edge cases

- **No internal sources available** (no Telegram CLI, no email CLI, no
  vault folder): Gate 1 is skipped; Phase 2 is marked "not applicable".
- **Operator unreachable** (no `AskUserQuestion` response within a
  pre-agreed timeout — 5 min default): treat as `skip internal`.
- **Ambiguous operator reply** (e.g. "maybe later"): do not proceed. Treat
  as `skip internal`. Prompt operators to pick from the option list
  explicitly on first re-run.

---

## Gate 2 — Write-only execution

The queries run **and** their results go to
`./osint-<slug>/phase-2-raw.md`. The agent **does not** load the raw
content into its own context.

### File shape

```
# Phase 2 Raw — <Name>

Generated: 2026-04-17 14:03
Sources queried: telegram (42 msgs matched), email (0 matches),
vault/crm/*.md (1 file matched).

---

### Finding 1
- Source: telegram (@somechat, 2024-03-12)
- Subject mentioned: yes
- Raw excerpt: [REDACTION_NEEDED — operator review pending]
- Auto-summary (safe): subject discussed a product launch with the operator.

### Finding 2
- Source: vault/crm/2024-deals.md:12
- Subject mentioned: yes
- Raw excerpt: [REDACTION_NEEDED — operator review pending]
- Auto-summary (safe): CRM notes a 2024 consulting engagement.

...

PROMOTION: <waiting for operator>
```

### Rules for this gate

- **Raw excerpts are not printed to stdout** — they live only in the file.
- **Auto-summaries are ≤ 1 sentence, no verbatim quotes, no PII beyond the
  subject's already-public identifiers.**
- **The agent's next tool call after the `Write` MUST be either
  `AskUserQuestion` (Gate 3) or the skill exit.** No other tool call is
  permitted between Gate 2 and Gate 3 — enforced by the SKILL.md prompt
  instructions.

### Edge cases

- **A query returns sensitive, unrelated content** (e.g. grep on the name
  matches a different person): still write to the file but tag the finding
  with `- Subject mentioned: uncertain — name-collision suspected`. Operator
  handles during Gate 3.
- **Phase 2 produces 0 findings**: write the file with the header + "0
  findings." line + `PROMOTION: n/a — nothing to promote`. Operator
  acknowledges in Gate 3; Phase 3 proceeds with a note.

---

## Gate 3 — Operator redaction window

### Question text (verbatim)

> *"Phase-2 raw file is at `./osint-<slug>/phase-2-raw.md`. Open it,
> redact anything you do not want to appear in the dossier (replace with
> `[REDACTED]`), and replace every `[REDACTION_NEEDED — …]` marker with
> either the approved excerpt, an `[INDIRECT: <one-line paraphrase>]`
> placeholder, or `[DROP]`. When done, add this exact line at the end of
> the file: `PROMOTION: APPROVED <your-initials> <ISO-date>`. Reply
> `approved` when saved."*

### Options

- `approved` → Gate 4.
- `skip internal — go to Phase 3` → skip Phase 2 entirely.
- `still redacting` → loop this question after 2 minutes.

### What the operator does in this window

- Open the raw file in their editor.
- For each finding with `[REDACTION_NEEDED — …]`:
  - Replace with an approved excerpt **iff** they want the paraphrase to be
    based on that specific wording — never if they want the text out of the
    dossier entirely.
  - Replace with `[INDIRECT: <paraphrase>]` if they want the agent to use
    the idea but not the wording.
  - Replace with `[DROP]` to keep the finding out of the dossier.
- Optionally add `[REDACTED]` in place of specific names/numbers inside any
  excerpt.
- Append the promotion line exactly: `PROMOTION: APPROVED VS 2026-04-17`.
- Save the file.
- Reply `approved`.

### Edge cases

- **Operator modifies fewer findings than Gate 2 recorded**: allowed —
  anything left as `[REDACTION_NEEDED]` will fail Gate 4 and cause the
  whole phase to be skipped. This is intended (fail-closed).
- **Operator deletes the file**: Gate 4 fails (no file). Phase 2 skipped.
- **Operator changes the subject name mid-review**: flagged as a
  name-collision escalation; Phase 2 skipped.

---

## Gate 4 — Promotion check

Performed by the agent, after reply `approved`:

1. `Read` `./osint-<slug>/phase-2-raw.md`.
2. Assert the last non-blank line matches the regex:
   `^PROMOTION: APPROVED \S+ \d{4}-\d{2}-\d{2}$`.
3. Assert no line contains the literal `REDACTION_NEEDED`.
4. If both pass: promote. Proceed to Phase 3 with internal data as Grade-I.
5. If either fails: abort Phase 2. Record in the dossier audit log:
   *"Internal intelligence: queried but not promoted (Gate 4 failed)."*
   Proceed to Phase 3 **without** internal data.

### Fail-open is never acceptable

If the agent detects any anomaly — the file is missing, the regex doesn't
match, there's still a `REDACTION_NEEDED` marker, or the file's mtime is
more recent than the Gate 3 reply — the default is **skip the phase**, not
"ask the operator again". The operator can always re-run the skill if they
want to retry Phase 2.

---

## What the dossier looks like after Phase 2

Every internal-origin insight appears in the dossier with:

- Grade: `I` (never `A`).
- Citation: `[internal, operator-approved YYYY-MM-DD]`.
- Paraphrased, not quoted.
- Audit log entry: "Internal intelligence: consulted, N findings promoted."

If Phase 2 was skipped for any reason, the audit log still appears, saying
"Internal intelligence: skipped (Gate N failed)" or "skipped (operator
declined)".

This makes the final dossier honest about its sources even when there's
nothing to show from the internal phase.

---

## If you're tempted to add a bypass

Don't. The gates are load-bearing. If a legitimate workflow feels blocked
by them, the fix is to make the gates more ergonomic (better prompts,
smarter auto-summary, clearer redaction syntax), not to add a
`--skip-gates` flag. Once such a flag exists, it will end up being set.
