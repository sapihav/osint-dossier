# Psychoprofile — Methodology

Lazy-loaded only in Phase 5 when psychoprofile was requested. Keep the base
SKILL.md light.

---

## What this is

A text-based inference about a subject's communication style and — optionally
— their MBTI / Big-Five profile. **Based solely on public text they wrote
themselves** (tweets, blog posts, podcast transcripts, conference talks).
Not a diagnostic, not a clinical assessment. Treat confidence as "medium at
best" regardless of how coherent the inference feels.

---

## Required inputs

Before running psychoprofile, you need **all** of:

- ≥ 500 words of self-authored text (1 long blog post, 1 podcast
  transcript, or ~30 substantive tweets).
- Author attribution for each sample — do not mix text that may have been
  ghostwritten, translated, or auto-generated.
- At least two *distinct* contexts (formal + informal, or written +
  spoken). The delta between contexts is the most informative signal.

If you cannot collect all three, **do not run psychoprofile.** Note in the
dossier: "Insufficient text samples for psychoprofile."

---

## Writing-style metrics (quantitative)

Compute and report:

- **Average sentence length** (words).
- **Self-reference rate** — frequency of "I / me / my" per 100 words.
- **Emoji density** — emojis per 100 words.
- **Hedging frequency** — per 100 words, count of "maybe", "probably",
  "I think", "in my opinion", "could be".
- **Declarative-vs-interrogative ratio** — periods vs question marks.
- **Lexical diversity** — type/token ratio over the first 500 words.

These are facts about the text. Report them. Do not over-interpret.

---

## MBTI inference (optional, confidence-capped)

For each of the four dimensions, assign a tentative value with evidence and
a confidence tier (high / medium / low). **Cap all single-dimension
confidences at medium unless a signal is overwhelming and cross-referenced.**

### I / E — Introversion / Extraversion
- Signals for E: frequent "we / us / our group", preference for
  conversational topics over solitary technical work, story-telling mode.
- Signals for I: long solo posts, deep-dive technical content, low
  @mentions per post.

### N / S — Intuition / Sensing
- Signals for N: abstract framing, frequent metaphors, future-focus,
  system-level vocabulary.
- Signals for S: concrete examples, specific numbers, present-tense
  observations.

### T / F — Thinking / Feeling
- Signals for T: argument-by-evidence, comfort with disagreement, few
  emotional adjectives.
- Signals for F: value-framed argument ("this is wrong / this matters"),
  emotional adjectives, concern for audience sentiment.

### J / P — Judging / Perceiving
- Signals for J: lists, plans, decisive conclusions, preference for
  closure.
- Signals for P: exploratory tone, "depends", multiple possibilities left
  open, rare final verdicts.

### Output format (in dossier)

```
- MBTI (tentative, low-medium confidence)
  - I/E: I (medium) — 8 of 10 analysed posts are solo technical deep-dives;
    self-reference rate 3.2/100.
  - N/S: N (medium) — abstract framing in 7/10; metaphor density high.
  - T/F: T (medium) — no emotional adjectives in conclusions, one public
    disagreement handled by citing evidence.
  - J/P: P (low) — exploratory tone dominant; 4/10 posts end without a
    specific next action.
  - Aggregate: INTP tentative. Re-evaluate with more samples.
```

---

## Big Five (optional, preferred over MBTI for defensibility)

Big Five has better empirical grounding. Use when the subject has enough
text and the operator wants a more defensible profile.

For each of the five dimensions, score **low / medium / high** with
evidence:

- **Openness** — abstract vocabulary, novel metaphors, willingness to
  engage with speculative topics.
- **Conscientiousness** — planning language, completion-focus,
  follow-through statements.
- **Extraversion** — topic-switching, conversational register,
  audience-orientation.
- **Agreeableness** — cooperative framing, softening language, other-focus.
- **Neuroticism** — emotional volatility across posts, negative-affect
  vocabulary, self-criticism.

---

## Context delta — the most informative signal

If the subject has text in two contexts (e.g. LinkedIn + Twitter, or
interview + Telegram channel), compare:

- Sentence length: longer or shorter in the informal context?
- Emoji density: delta.
- Hedging frequency: delta.
- Self-reference rate: delta.

The **direction** of the delta is often more informative than the absolute
values. A large "formal vs informal" swing suggests adaptability; a small
swing suggests consistency.

---

## Hard rules

1. **Never infer family, DOB, age, sexuality, health, politics, religion
   from text style alone.** These are either Grade-A sourced or absent.
2. **Never include Zodiac** unless DOB is confirmed at Grade A or B.
3. **Never use Phase-2 internal text** for psychoprofile inputs —
   psychoprofile is always from public, attributable samples.
4. **Always tag confidence.** Never present MBTI / Big-Five as definite.
5. **Always list the samples used** in the dossier audit line. A
   psychoprofile without a sample list is not a psychoprofile, it's a
   guess.

---

## When to skip psychoprofile entirely

- Subject has < 500 words of attributed text → skip.
- Subject is known to use ghostwriters / PR writers → skip (unattributable).
- Operator didn't explicitly ask → skip; mention as "available if
  requested" in the dossier.
- Samples are all in one register (e.g. only press releases) → skip.
