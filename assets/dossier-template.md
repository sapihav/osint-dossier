<!--
  Dossier template — render via the osint-dossier skill, Phase 7.
  Placeholder syntax (orchestrator handles substitution):
    {{name}}              — single value
    {{#if name}}…{{/if}}  — conditional block
    {{#name}}…{{/name}}   — repeat block, one rendering per item
  Rules (applied by the orchestrator, not the consumer of the rendered file):
   - Bullet lists only; no tables in the body. Many downstream renderers mangle tables.
   - Cite every non-internal claim with a URL.
   - If internal data was consulted, the audit-log line must appear regardless of
     whether any internal content was used.
   - In the Facts list, `sources` and `internal` are mutually exclusive — set
     exactly one per fact. Setting both renders both clauses inline.
   - Grade legend:
       A — confirmed (≥2 independent public sources, or official verified profile,
           or direct public statement)
       B — probable (one credible source: LinkedIn, official media, company site)
       C — inferred (indirect evidence: timezone from post times, geotag,
           2nd-degree connections)
       D — unverified (single low-credibility mention)
       I — internal, operator-approved (Phase 2; paraphrase only; never counts
           toward A-grade confirmation)
-->

# OSINT Dossier — {{subject_name}}

## Summary
{{summary_3_to_5_sentences}}

## Facts
{{#facts}}
- {{claim}} — Grade {{grade}} — {{#if sources}}Sources: {{sources_as_markdown_links}}{{/if}}{{#if internal}}Internal, operator-approved {{approval_date}}, paraphrase only{{/if}}
{{/facts}}

## Psychoprofile
{{#if psychoprofile_run}}
{{psychoprofile_block}}
{{/if}}
{{#if psychoprofile_skipped}}
Not run.
{{/if}}

## Gaps
{{#gaps}}
- {{description}} — {{render_affordance}}
  - {{#if not_yet_attempted}}Not yet attempted. Try: {{where_and_how}}{{/if}}
  - {{#if ladder_exhausted}}Tried {{tiers_tried_summary}} — no public source produced a match. Spending more here is probably wasted; treat as a residual gap.{{/if}}
  - {{#if standard_gap}}Try: {{where_and_how}} (already attempted: {{tiers_tried_summary}}).{{/if}}
{{/gaps}}

## Coverage
- Slots met: {{met_count}}/{{total_slots}}{{#if applies_when_skipped}} ({{applies_when_skipped}} not applicable this run){{/if}}
- Grade distribution across met slots: {{grade_distribution}}
- Process attestation:
  - Contradictions resolved: {{contradictions_resolved}}
  - Internal-intelligence phase: {{phase_2_attested}}{{#if phase_2_incomplete}} ⚠ Phase 2 started but did not reach a terminal gate{{/if}}

## Audit log
- Tools used: {{tool_call_summary}}
- Internal intelligence: {{internal_intel_state}}
- Approx. total spend: ${{total_spend_usd}}
- Elapsed: {{elapsed_human}}
- Stage manifest: {{stage_manifest}}
