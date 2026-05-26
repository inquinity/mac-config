# OSS Application Security Review Rubric

## Checklist

Use this rubric after reading `SKILL.md`. Keep the review static-first unless the user approves execution.

### Data Exfiltration

- Identify all outbound network paths: HTTP clients, WebSockets, gRPC, SMTP, DNS, analytics SDKs, error reporting, telemetry, webhooks, update checks, binary downloads, and subprocess network tools.
- Trace what each egress path can send: prompts, queries, files, logs, environment variables, tokens, cookies, headers, local paths, clipboard contents, system metadata, or command output.
- Check for covert or indirect egress: encoded payloads, URL query parameters, referrers, image beacons, package scripts, crash reports, model/tool call transcripts, and pasted content.
- Verify user consent, configuration controls, opt-out behavior, redaction, batching, retention, and destination ownership.

### Token And Password Security

- Locate credential inputs: environment variables, `.env` files, config files, CLI flags, OAuth, browser cookies, keychains, credential helpers, cloud SDK profiles, Kubernetes config, CI secrets, and interactive prompts.
- Check whether secrets are logged, persisted, embedded in generated output, sent to third parties, exposed in exceptions, committed as examples, copied into cache files, or passed to child processes.
- Evaluate masking and redaction. Redaction should happen before logging or telemetry, not only in the UI.
- Check token scope and lifetime. Flag broad tokens, long-lived credentials, missing rotation guidance, unnecessary write scopes, and ambiguous permission prompts.

### Query And Data-Source Access

- Map each query surface: SQL, GraphQL, REST search, vector search, SaaS APIs, local indexes, browser history, chat transcripts, logs, issue trackers, repo search, file search, and agent connectors.
- Identify what the app can read, write, delete, or export from each surface.
- Check whether query access is tenant-scoped, path-scoped, project-scoped, user-scoped, or token-scoped. Flag broad cross-tenant or whole-account access.
- Review prompt/tool orchestration for query injection, tool-confusion, excessive result forwarding, and hidden context leakage.

### Credential And Host Access

- Search for access to home directories, shell profiles, SSH keys, GPG keys, cloud config, npm/pip credentials, Docker auth, Kubernetes config, browser profiles, password stores, OS keychains, and application support folders.
- Review command execution, shell interpolation, subprocess environment inheritance, temporary files, file watchers, recursive scans, and archive creation.
- Flag broad reads such as `$HOME`, `/`, `~/Library`, `%APPDATA%`, mounted host paths, unrestricted globbing, or hidden-file traversal unless the app has a clear need and user-visible control.

### Sandbox And Least Privilege

- Identify the intended sandbox: project-only source review, browser extension permissions, desktop app entitlements, container mounts, CLI working directory, web app origin, mobile permission set, or cloud role.
- Compare declared permissions to actual needs. Flag wildcard host permissions, broad filesystem mounts, privileged containers, host networking, Docker socket access, full repo or org scopes, and write permissions where read-only would work.
- Check whether deny-by-default controls exist for network, filesystem, credentials, tool calls, plugins, and generated artifacts.

### Supply Chain And Build Surface

- Inspect manifests and lockfiles: `package.json`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `requirements*.txt`, `pyproject.toml`, `poetry.lock`, `Pipfile.lock`, `go.mod`, `go.sum`, `Cargo.toml`, `Cargo.lock`, `pom.xml`, `build.gradle`, `Gemfile.lock`, and Dockerfiles.
- Inspect lifecycle hooks: `preinstall`, `install`, `postinstall`, `prepare`, `prepublish`, `scripts`, `Makefile`, `justfile`, setup scripts, GitHub Actions, release scripts, and generated binary fetchers.
- Flag dependency confusion risk, unpinned versions, direct Git dependencies, binary downloads without checksum verification, broad CI tokens, and scripts that read or upload local files.

## Search Patterns

Use `rg` first. Tune language-specific terms to the project.

```text
fetch|axios|got|request|http\.|https\.|WebSocket|grpc|sendBeacon|XMLHttpRequest
telemetry|analytics|sentry|datadog|segment|posthog|amplitude|crash|metrics|track
process\.env|os\.environ|getenv|dotenv|SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY
child_process|exec\(|spawn\(|subprocess|system\(|popen|shell=True
readFile|writeFile|readdir|glob|walk|fs\.|path\.|open\(|FileReader
HOME|USERPROFILE|APPDATA|Library/Application Support|\.ssh|\.aws|\.kube|\.docker|keychain|keyring
clipboard|cookies|localStorage|sessionStorage|browser\.history|tabs|activeTab
graphql|SELECT |INSERT |UPDATE |DELETE |query\(|search\(|vector|embedding
postinstall|preinstall|prepare|curl |wget |Invoke-WebRequest|base64|eval\(
```

## Severity Guide

- Critical: Credible path to secret theft, arbitrary code execution in normal install/run flow, silent exfiltration of sensitive user data, credential forwarding to an untrusted destination, or broad destructive access with weak controls.
- High: Broad credential, filesystem, query, tenant, or network access that exceeds the stated purpose; weak sandboxing around sensitive data; unsafe lifecycle hooks; or token leakage through logs, telemetry, or child processes.
- Medium: Sensitive access with partial user control, unclear consent, insufficient redaction, excessive scopes, risky defaults, dependency/build concerns, or plausible injection into query/tool flows.
- Low: Hardening gaps, missing documentation, weak opt-out clarity, incomplete least-privilege explanation, or issues requiring unlikely configuration.

## Finding Template

```markdown
### [Severity] Short finding title

- Evidence: `path/to/file.ext:line`
- Impact: What data, credential, query, or permission can be exposed or misused.
- Path: How the code reaches the risky behavior.
- Fix: Narrow, actionable remediation.
```

## Access Map Template

```markdown
| Area | Observed access | Evidence | Risk | Notes |
| --- | --- | --- | --- | --- |
| Credentials |  |  |  |  |
| Queries/data sources |  |  |  |  |
| Filesystem |  |  |  |  |
| Network egress |  |  |  |  |
| Sandbox/permissions |  |  |  |  |
| Build/CI/dependencies |  |  |  |  |
```

## Review Discipline

- Do not mark a category safe just because no issue was found in a quick search. Say what was reviewed and what remains unreviewed.
- Prefer "No evidence found in reviewed files" over "not vulnerable" when coverage is partial.
- When a project has many generated or vendored files, sample enough to identify generation sources, then focus on source templates and build steps.
- When runtime behavior matters, propose a dry-run or instrumented run plan and ask for approval before executing untrusted code.
