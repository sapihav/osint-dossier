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
- {{gap}} → look at: {{where_and_how}}
{{/gaps}}

## Coverage & Depth
- Coverage: {{coverage_passed}}/9 checks pass{{#if coverage_failures}} ({{coverage_failures_summary}}){{/if}}
- Depth Score: {{depth_score}}

## Audit log
- Tools used: {{tool_call_summary}}
- Internal intelligence: {{internal_intel_state}}
- Approx. total spend: ${{total_spend_usd}}
- Elapsed: {{elapsed_human}}
- Stage manifest: {{stage_manifest}}
