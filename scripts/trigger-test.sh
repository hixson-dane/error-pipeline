#!/usr/bin/env bash
# trigger-test.sh
#
# Simulates a Rollbar/Datadog webhook by dispatching a `runtime_error`
# repository_dispatch event to the error-pipeline repo.
#
# Prerequisites:
#   - The `gh` CLI must be installed and authenticated.
#   - GITHUB_OWNER environment variable must be set to your GitHub username
#     or organization name.
#
# Usage:
#   export GITHUB_OWNER=<your-github-username-or-org>
#   bash scripts/trigger-test.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
if [ -z "${GITHUB_OWNER:-}" ]; then
  echo "❌ Error: GITHUB_OWNER environment variable is required." >&2
  echo "   Set it to your GitHub username or organization name:" >&2
  echo "   export GITHUB_OWNER=<your-github-username-or-org>" >&2
  exit 1
fi

OWNER="${GITHUB_OWNER}"
PIPELINE_REPO="${OWNER}/error-pipeline"
TARGET_REPO="${OWNER}/error-fix-demo-app"

# ---------------------------------------------------------------------------
# Build the payload
# ---------------------------------------------------------------------------
ERROR_TITLE="AttributeError: 'NoneType' object has no attribute 'name'"

STACK_TRACE="Traceback (most recent call last):
  File \"app/routes/user_routes.py\", line 32, in get_user_profile
    display_name = user_service.get_user_display_name(user_id)
  File \"app/services/user_service.py\", line 17, in get_user_display_name
    return user.name
AttributeError: 'NoneType' object has no attribute 'name'

Note: user ID 999 does not exist in the database."

# ---------------------------------------------------------------------------
# Dispatch the event
# ---------------------------------------------------------------------------
echo "🚀 Dispatching runtime_error event to ${PIPELINE_REPO}..."
echo "   Target repo for fix: ${TARGET_REPO}"
echo ""

gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "/repos/${PIPELINE_REPO}/dispatches" \
  --field "event_type=runtime_error" \
  --field "client_payload[title]=${ERROR_TITLE}" \
  --field "client_payload[error_message]=${ERROR_TITLE}" \
  --field "client_payload[stack_trace]=${STACK_TRACE}" \
  --field "client_payload[environment]=production" \
  --field "client_payload[severity]=critical" \
  --field "client_payload[error_url]=https://rollbar.com/item/12345" \
  --field "client_payload[target_repo]=${TARGET_REPO}" \
  --field "client_payload[base_branch]=main"

echo ""
echo "✅ Event dispatched successfully!"
echo ""
echo "Next steps:"
echo "  1. Watch the Actions run:  https://github.com/${PIPELINE_REPO}/actions"
echo "  2. View the created issue: https://github.com/${TARGET_REPO}/issues"
