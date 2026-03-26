# Copilot Instructions

## What This Repo Does

This is a **GitHub Actions-only repository** — there is no application code. The entire logic lives in `.github/workflows/error-to-copilot.yml`.

The pipeline receives a `repository_dispatch` event (`event_type: runtime_error`) from an external error-monitoring service (Rollbar, Datadog, etc.), validates the payload, deduplicates against existing issues, and creates a GitHub issue on a **separate target repository** (`owner/error-fix-demo-app`) assigned to the Copilot coding agent (`copilot-swe-agent[bot]`).

```
Error service → repository_dispatch → this repo's workflow → issue on target repo → Copilot agent → PR
```

## Triggering / Testing

Simulate a webhook dispatch:

```bash
export GITHUB_OWNER=<your-github-username-or-org>
bash scripts/trigger-test.sh
```

Requires the `gh` CLI to be authenticated. The script dispatches a sample `AttributeError` event and prints the Actions and Issues URLs to monitor progress.

To dispatch manually:
```bash
gh api --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/YOUR_ORG/error-pipeline/dispatches \
  --field "event_type=runtime_error" \
  --field "client_payload[title]=<error title>" \
  --field "client_payload[error_message]=<error message>" \
  --field "client_payload[stack_trace]=<stack trace>" \
  --field "client_payload[target_repo]=YOUR_ORG/error-fix-demo-app" \
  --field "client_payload[base_branch]=main"
```

## Workflow Architecture (`error-to-copilot.yml`)

The single job `create-fix-issue` runs these steps in order:

1. **Validate payload** — ensures `title`, `stack_trace`, `error_message`, and `target_repo` are present; fails fast if any are missing.
2. **Parse error payload** — extracts all fields from `client_payload` and writes them to `GITHUB_OUTPUT` for downstream steps.
3. **Check for duplicate issues** — searches open issues on the *target repo* by sanitized error message; sets `duplicate=true/false` on output.
4. **Build issue body** — formats a Markdown issue body with a metadata table, error message block, stack trace, and fixed instructions for the Copilot agent. Steps 4–7 are skipped if `duplicate=true`.
5. **Create issue** — posts the issue to the target repo via `gh api`, ensures `bug`, `automated`, and `copilot-fix` labels exist first (idempotent), assigns to `copilot-swe-agent[bot]`.
6. **Write step summary** — appends a success table to `$GITHUB_STEP_SUMMARY`.
7. **Write duplicate-skip summary** — appends a warning to `$GITHUB_STEP_SUMMARY` when a duplicate was detected.

## Key Conventions

**`permissions: {}`** — The workflow explicitly revokes all default `GITHUB_TOKEN` permissions. All GitHub API calls use `secrets.COPILOT_DISPATCH_PAT` (a fine-grained PAT scoped to both this repo and the target repo with Issues, Contents, Actions, and Pull requests read/write).

**Multiline `GITHUB_OUTPUT` values** — Stack traces and issue bodies use heredoc-style unique delimiters (e.g., `<<__STACK__`) to safely pass multiline content between steps. Do not use simple `key=value` for fields that may contain newlines.

**Issues are created on the target repo, not this repo** — `TARGET_REPO` comes from `client_payload.target_repo` (`owner/repo` format). This repo only orchestrates; the fix work happens elsewhere.

**Duplicate detection** — Sanitizes the error message (strips `"`, `\`, `:`, `'`, `(`, `)`) and caps at 100 chars before using it as a GitHub issue search query to avoid false negatives from special characters.

## `client_payload` Schema

| Field | Required | Default | Description |
|---|---|---|---|
| `title` | ✅ | — | Short error title |
| `error_message` | ✅ | — | Full error message (used for dedup) |
| `stack_trace` | ✅ | — | Full stack trace text |
| `target_repo` | ✅ | — | `owner/repo` where the fix issue is created |
| `environment` | No | `"unknown"` | e.g. `"production"` |
| `severity` | No | `"error"` | e.g. `"critical"`, `"warning"` |
| `error_url` | No | `"N/A"` | Link to the error in the monitoring tool |
| `base_branch` | No | `"main"` | Branch Copilot should base its fix on |
