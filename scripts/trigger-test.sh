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
#   bash scripts/trigger-test.sh [OPTIONS]
#
# Options:
#   -r, --target-repo OWNER/REPO      Target repo where the fix issue is created.
#                                     Default: ${GITHUB_OWNER}/error-fix-demo-app
#   -s, --stack-trace "TEXT"          Inline stack trace string.
#   -f, --stack-trace-file PATH       Path to a file containing the stack trace.
#                                     (--stack-trace and --stack-trace-file are mutually exclusive)
#
# Examples:
#   bash scripts/trigger-test.sh --target-repo myorg/my-app
#   bash scripts/trigger-test.sh --stack-trace-file /tmp/trace.txt
#   bash scripts/trigger-test.sh -r myorg/my-app -f /tmp/trace.txt

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse optional flags
# ---------------------------------------------------------------------------
FLAG_TARGET_REPO=""
FLAG_STACK_TRACE=""
FLAG_STACK_TRACE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--target-repo)
      FLAG_TARGET_REPO="$2"; shift 2 ;;
    -s|--stack-trace)
      FLAG_STACK_TRACE="$2"; shift 2 ;;
    -f|--stack-trace-file)
      FLAG_STACK_TRACE_FILE="$2"; shift 2 ;;
    *)
      echo "❌ Unknown flag: $1" >&2
      echo "   Run 'bash scripts/trigger-test.sh --help' for usage." >&2
      exit 1 ;;
  esac
done

if [ -n "$FLAG_STACK_TRACE" ] && [ -n "$FLAG_STACK_TRACE_FILE" ]; then
  echo "❌ Error: --stack-trace and --stack-trace-file are mutually exclusive." >&2
  exit 1
fi

if [ -n "$FLAG_STACK_TRACE_FILE" ] && [ ! -r "$FLAG_STACK_TRACE_FILE" ]; then
  echo "❌ Error: Cannot read stack trace file: ${FLAG_STACK_TRACE_FILE}" >&2
  exit 1
fi

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
TARGET_REPO="${FLAG_TARGET_REPO:-${OWNER}/error-fix-demo-app}"

# ---------------------------------------------------------------------------
# Build the payload
# ---------------------------------------------------------------------------
ERROR_TITLE="AttributeError: 'NoneType' object has no attribute 'name'"

DEFAULT_STACK_TRACE="Traceback (most recent call last):
  File \"app/routes/user_routes.py\", line 32, in get_user_profile
    display_name = user_service.get_user_display_name(user_id)
  File \"app/services/user_service.py\", line 17, in get_user_display_name
    return user.name
AttributeError: 'NoneType' object has no attribute 'name'

Note: user ID 999 does not exist in the database."

if [ -n "$FLAG_STACK_TRACE_FILE" ]; then
  STACK_TRACE="$(cat "$FLAG_STACK_TRACE_FILE")"
elif [ -n "$FLAG_STACK_TRACE" ]; then
  STACK_TRACE="$FLAG_STACK_TRACE"
else
  STACK_TRACE="$DEFAULT_STACK_TRACE"
fi

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
