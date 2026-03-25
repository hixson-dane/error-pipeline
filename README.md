# error-pipeline

Middleware between error-monitoring services (Rollbar, Datadog, etc.) and the
GitHub Copilot coding agent.  When a runtime error is detected in production,
this repo receives a webhook event, creates a GitHub issue on the affected
repository, and automatically assigns it to the Copilot coding agent — which
researches the stack trace, locates the root cause, and opens a pull request
with a proposed fix.

---

## Architecture

```
┌──────────────────┐    webhook / API call    ┌──────────────────────────┐
│  Error Service   │─────────────────────────▶│  Translation Proxy       │
│  (Rollbar /      │                          │  (optional — Lambda,     │
│   Datadog)       │                          │   Cloudflare Worker, …)  │
└──────────────────┘                          └────────────┬─────────────┘
                                                           │ repository_dispatch
                                                           │ event_type: runtime_error
                                                           ▼
                                              ┌──────────────────────────┐
                                              │  YOUR_ORG/error-pipeline │
                                              │  .github/workflows/      │
                                              │  error-to-copilot.yml    │
                                              │                          │
                                              │  • Validates payload     │
                                              │  • Checks for duplicates │
                                              │  • Creates GitHub issue  │
                                              └────────────┬─────────────┘
                                                           │ Issue assigned to
                                                           │ copilot-swe-agent[bot]
                                                           ▼
                                              ┌──────────────────────────┐
                                              │  Copilot Coding Agent    │
                                              │                          │
                                              │  • Reads stack trace     │
                                              │  • Analyzes codebase     │
                                              │  • Opens PR with fix     │
                                              └────────────┬─────────────┘
                                                           │
                                                           ▼
                                              ┌──────────────────────────┐
                                              │  You review & merge PR   │
                                              └──────────────────────────┘
```

---

## Prerequisites

1. **GitHub Copilot plan** – Pro, Pro+, Business, or Enterprise with the
   [Copilot coding agent](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent)
   feature enabled.
2. **Fine-grained Personal Access Token (PAT)** with the following permissions
   scoped to **both** this repo and the target fix repo:

   | Permission      | Access       |
   |-----------------|--------------|
   | Issues          | Read & Write |
   | Contents        | Read & Write |
   | Actions         | Read & Write |
   | Pull requests   | Read & Write |

3. **Companion `error-fix-demo-app` repository** – the repo where Copilot will
   open the fix PR.  Copilot coding agent must be enabled for that repo.

---

## Setup

### 1. Create the fine-grained PAT

1. Go to **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens**.
2. Click **Generate new token**.
3. Under **Repository access**, select **Only select repositories** and choose
   both `error-pipeline` and `error-fix-demo-app`.
4. Under **Permissions**, grant the four permissions listed above (Issues,
   Contents, Actions, Pull requests) as **Read and write**.
5. Click **Generate token** and copy the value.

### 2. Store the PAT as a repository secret

1. In this repo (`error-pipeline`), go to
   **Settings → Secrets and variables → Actions**.
2. Click **New repository secret**.
3. Name: `COPILOT_DISPATCH_PAT`
4. Value: paste the token from step 1.
5. Click **Add secret**.

### 3. Enable the Copilot coding agent on `error-fix-demo-app`

Follow the
[GitHub documentation](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent)
to enable the Copilot coding agent for the target repository.

---

## Running the Demo

The `scripts/trigger-test.sh` script simulates a Rollbar/Datadog webhook by
dispatching a sample `runtime_error` event.

```bash
# Set your GitHub username or org
export GITHUB_OWNER=<your-github-username>

# Run the script (requires the gh CLI to be installed and authenticated)
bash scripts/trigger-test.sh
```

The script will:

1. Dispatch a `runtime_error` event to this repo.
2. Print the Actions URL to monitor the workflow run.
3. Print the Issues URL to see the created issue.

The Copilot coding agent will then analyze the stack trace and open a pull
request on `error-fix-demo-app`.

---

## Connecting a Real Error Service

Both Rollbar and Datadog support outbound webhooks.  Because their webhook
payloads differ from the format expected by this pipeline, you need a small
**translation proxy** (e.g., an AWS Lambda or Cloudflare Worker) that:

1. Receives the raw webhook from Rollbar/Datadog.
2. Extracts the relevant fields (error message, stack trace, environment, etc.).
3. Calls the GitHub `repository_dispatch` API with the normalized payload.

Below is a minimal Cloudflare Worker / AWS Lambda skeleton as a starting point:

```javascript
// translation-proxy.js — adapt to your Rollbar/Datadog payload schema
export default {
  async fetch(request, env) {
    const raw = await request.json();

    // --- Extract fields from the error-service payload (adjust per service) ---
    const item = raw.data?.item || raw;
    const trace = item.last_occurrence?.body?.trace;
    const errorMessage = trace?.exception
      ? `${trace.exception.class}: ${trace.exception.message}`
      : item.message || "Unknown error";
    const stackTrace = trace?.frames
      ?.map(f => `  File "${f.filename}", line ${f.lineno}, in ${f.method}`)
      .join("\n") || "No stack trace available";
    const targetRepo = env.TARGET_REPO; // set as Worker env var

    // --- Dispatch to the error-pipeline ---
    await fetch(
      `https://api.github.com/repos/${env.PIPELINE_REPO}/dispatches`,
      {
        method: "POST",
        headers: {
          Accept: "application/vnd.github+json",
          Authorization: `Bearer ${env.GITHUB_PAT}`,
          "X-GitHub-Api-Version": "2022-11-28",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          event_type: "runtime_error",
          client_payload: {
            title: errorMessage,
            error_message: errorMessage,
            stack_trace: stackTrace,
            environment: item.environment || "production",
            severity: item.level || "error",
            error_url: item.url || "N/A",
            target_repo: targetRepo,
            base_branch: "main",
          },
        }),
      }
    );

    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  },
};
```

---

## Payload Format Reference

The `repository_dispatch` event must have `event_type: runtime_error` and a
`client_payload` with the following fields:

| Field           | Required | Default     | Description                                          |
|-----------------|----------|-------------|------------------------------------------------------|
| `title`         | ✅ Yes   | —           | Short error title / exception message                |
| `error_message` | ✅ Yes   | —           | Full error message (used for duplicate detection)    |
| `stack_trace`   | ✅ Yes   | —           | Full stack trace text                                |
| `target_repo`   | ✅ Yes   | —           | `owner/repo` where the fix issue should be created   |
| `environment`   | No       | `"unknown"` | e.g. `"production"`, `"staging"`                    |
| `severity`      | No       | `"error"`   | e.g. `"critical"`, `"error"`, `"warning"`           |
| `error_url`     | No       | `"N/A"`     | Link to the error in Rollbar/Datadog                 |
| `base_branch`   | No       | `"main"`    | Branch Copilot should base the fix branch on         |

### Example dispatch call

```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  /repos/YOUR_ORG/error-pipeline/dispatches \
  --field "event_type=runtime_error" \
  --field "client_payload[title]=AttributeError: 'NoneType' object has no attribute 'name'" \
  --field "client_payload[error_message]=AttributeError: 'NoneType' object has no attribute 'name'" \
  --field "client_payload[stack_trace]=Traceback (most recent call last):
  File \"app/services/user_service.py\", line 17, in get_user_display_name
    return user.name
AttributeError: 'NoneType' object has no attribute 'name'" \
  --field "client_payload[environment]=production" \
  --field "client_payload[severity]=critical" \
  --field "client_payload[error_url]=https://rollbar.com/item/12345" \
  --field "client_payload[target_repo]=YOUR_ORG/error-fix-demo-app" \
  --field "client_payload[base_branch]=main"
```
