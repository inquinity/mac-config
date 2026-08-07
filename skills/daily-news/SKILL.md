---
name: daily-news
description: Create concise, high-signal recent technology news briefings covering the last week by default, organized by topic and section, with summaries that may synthesize multiple sources and a sources list under every summary. Use when asked for daily news, weekly technology news, recent technology news, important AI news, software security news, quantum computing news, technology trends, cloud computing news, or a curated multi-source tech briefing.
---

# Daily News

## Overview

Produce a quality-first technology news briefing. Favor importance, reliability, and synthesis over volume.

Always browse or otherwise verify current information before writing a report. News is time-sensitive; do not rely on model memory.

## Workflow

1. Establish the report window. Default to the last 7 calendar days unless the user gives another range. For "daily news," still scan the last week and prioritize the most important recent items. State the exact dates covered.
2. Review the source registry in `references/source-registry.md`.
3. Scan the primary sources first. Use site search, RSS feeds, section pages, or web search constrained to the source domains when available.
4. Expand only when needed. If a story appears important but the listed sources are thin, use additional reputable primary or specialist sources and record them.
5. Select a small set of important items. Prefer fewer strong stories over many shallow entries.
6. Cross-check significant claims across at least two sources when practical, especially for security incidents, vulnerabilities, model releases, acquisitions, legal/regulatory actions, and financial claims.
7. Write the report using the required format below.

## Topic Scope

Use these default sections:

- AI
- Software Security
- Quantum Computing
- Technology Trends
- Cloud Computing

Omit a section if there are no important recent items. Add a short `Other Notable Technology` section only when an important item does not fit the default sections.

## Selection Standards

Include an item when it has meaningful impact for technology leaders, builders, defenders, researchers, or operators. Strong signals include:

- A material security vulnerability, campaign, breach, malware family, exploit technique, or defensive guidance.
- A major AI model, product, research result, policy, infrastructure change, safety issue, or ecosystem shift.
- A quantum computing milestone, credible research advance, standards update, or commercialization signal.
- A cloud platform launch, outage, pricing/licensing shift, architecture pattern, or operational/security impact.
- A trend with evidence across multiple sources, not just commentary.

Avoid low-signal items such as routine product marketing, thin funding announcements, duplicated wire copy, speculative hot takes, or single-source rumors unless the source is authoritative and the impact is clear.

## Required Report Format

Use this structure:

```markdown
# Daily Technology News - YYYY-MM-DD

Coverage: Month D, YYYY to Month D, YYYY

## Executive Summary

- 3-5 bullets summarizing the most important developments.

## AI

### Story Title

One concise paragraph explaining what happened and why it matters. If multiple sources contribute, synthesize them into one coherent summary.

sources:
- Site Name - URL
- Site Name - URL

## Software Security

...

## Recommend Sources

- Site Name - URL - Reason to consider adding it to the main source list.
```

Requirements:

- Put `sources:` directly below every story summary.
- Include source URLs, not just publication names.
- Use one paragraph per story unless extra detail is necessary.
- Keep source lists limited to sources actually used for that summary.
- If no new source recommendations are warranted, write `No additions recommended today.`
- Do not include unsupported certainty. Use measured language when facts are emerging.

## Source Handling

Use the source registry as the baseline, but do not treat it as exhaustive. Add sources to `Recommend Sources` only when they repeatedly contribute important, reliable, or primary information not well covered by the baseline list.

Prefer primary sources for official announcements, standards, research papers, advisories, CVEs, and incident disclosures. Prefer specialist reporting for context, impact, and independent analysis.

For security stories, prioritize original advisories, vendor research, CVE/NVD records, CISA KEV, CERT/CC, or affected vendor statements when available. Use news coverage to explain significance and timeline.

## Quality Checks

Before finalizing:

- Confirm the report covers the requested date range.
- Confirm each story belongs in its section and meets the importance threshold.
- Confirm every summary has a `sources:` list.
- Confirm any recommended source is not already in the main source registry.
- Confirm copied language is minimal and summaries are original synthesis.
