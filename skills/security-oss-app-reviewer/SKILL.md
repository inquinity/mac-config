---
name: security-oss-app-reviewer
description: Static-first security assessment workflow for open source application source code. Use when reviewing OSS apps, forks, plugins, desktop apps, CLIs, browser extensions, web apps, or agent tools for data exfiltration, token and password handling, credential access, query or data-source access, sandbox boundaries, filesystem reach, network egress, telemetry, dependency or CI risk, and least-privilege concerns.
---

# Security OSS App Reviewer

## Overview

Assess OSS application source for security exposure before trusting, running, installing, or integrating it. Keep the review static-first, evidence-based, and scoped to what the code can access or transmit.

## Operating Rules

- Inspect local context first, including `AGENTS.md`, `CLAUDE.md`, manifests, lockfiles, CI, build scripts, install scripts, Dockerfiles, and runtime entrypoints.
- Do not execute untrusted app code, install dependencies, run package scripts, or make network calls unless the user explicitly approves that exact action or a local policy allowlist covers it.
- Do not print secret values. Refer to sensitive findings by variable name, file path, config key, or redacted prefix only.
- Treat shell scripts, package lifecycle hooks, test setup, generated clients, extension manifests, prompts, and CI workflows as executable attack surface.
- Prefer file and line evidence over general claims. If evidence is inferred across files, cite each relevant file.
- Separate confirmed behavior from plausible risk. State assumptions and unknowns clearly.

## Workflow

1. Define scope.
   Identify application type, trust boundary, runtime environment, reviewed commit or directory, and whether generated/vendor code is in scope.

2. Build an access map.
   List the code paths that can read local files, environment variables, credential stores, browser or app profiles, databases, query APIs, cloud SDKs, sockets, clipboard, system commands, and user-provided input.

3. Build an egress map.
   List network destinations, telemetry clients, analytics, webhooks, uploads, subprocess calls, DNS usage, package registry behavior, and update mechanisms. Note whether user data, prompts, queries, tokens, logs, or files can leave the system.

4. Review credential handling.
   Trace token/password acquisition, storage, logging, forwarding, masking, rotation, and permission scope. Include `.env`, config files, keychains, credential helpers, cloud profiles, CI secrets, OAuth flows, cookies, and API clients.

5. Review query and data-source access.
   Identify what databases, search indexes, SaaS APIs, GraphQL/REST endpoints, local query logs, prompt histories, or connector-backed sources the app can query. Check whether access is constrained by tenant, project, path, user, or token scope.

6. Review sandbox boundaries.
   Determine whether the app stays inside the expected project directory and approved runtime sandbox. Flag unnecessary access to home directories, shell profiles, SSH keys, cloud config, Kubernetes config, browser profiles, password managers, clipboard, device APIs, host mounts, or broad container volumes.

7. Review supply chain and lifecycle hooks.
   Inspect dependency manifests, lockfiles, package scripts, postinstall hooks, binary downloads, vendored artifacts, GitHub Actions, Docker builds, release scripts, and auto-update code. Do not fetch package metadata unless approved.

8. Produce findings.
   Lead with actionable findings ordered by severity. Use `file:line` evidence, describe impact, explain exploit or misuse path, and propose narrow remediation. Include "No finding" only when the reviewed evidence actually supports it.

## Reference

Read `references/review-rubric.md` when performing a real assessment. It contains the checklist, search patterns, severity guide, and report template.

## Report Shape

Use this order unless the user asks for a different format:

1. Findings, highest severity first.
2. Access map: data, queries, credentials, filesystem, network.
3. Sandbox assessment and least-privilege gaps.
4. Open questions and assumptions.
5. Review coverage, skipped areas, and commands run.

When no issues are found, say that clearly and list residual risk from unreviewed generated code, dependencies, runtime behavior, or unavailable configuration.
