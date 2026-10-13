#!/usr/bin/env bash
# Checks that the repository is safe to have a self-hosted runner (brief
# mac-001a, Must 3 and 7). Run by the owner on the host, with `gh` logged in
# as an admin of the repository, before the runner is registered and whenever
# a workflow that runs on the Mac changes. See docs/MAC_RUNNER.md.
#
#   tools/mac/check-repo.sh
#
# It fails unless:
#   - fork pull requests need approval for all external contributors, so no
#     outside workflow run reaches the runner without the owner's click;
#   - no workflow with a job on a self-hosted runner has a pull_request or
#     pull_request_target trigger, so a Mac job never starts from a pull
#     request (tools/lib/mac-workflows.luau, which tools/check.sh runs too).
#
# Environment:
#   RUNNER_REPO   owner/name (default: laazyj/amy-and-the-rainforest-roblox)
set -euo pipefail
cd "$(dirname "$0")/../.."

REPO="${RUNNER_REPO:-laazyj/amy-and-the-rainforest-roblox}"
failed=0

echo "== Fork pull requests"
command -v gh >/dev/null || {
	echo "error: the GitHub CLI (gh) is needed: brew install gh" >&2
	exit 1
}
policy="$(gh api "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy 2>/dev/null || true)"
if [ "$policy" = "all_external_contributors" ]; then
	echo "ok: approval is required for all external contributors"
else
	failed=1
	echo "error: $REPO must require approval for all external contributors (it is '${policy:-unreadable: is gh logged in as an admin?}')." >&2
	echo "  Settings -> Actions -> General -> 'Require approval for all external contributors', or:" >&2
	echo "  gh api -X PUT repos/$REPO/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors" >&2
fi

echo "== Workflows that run on the Mac (also a tier 0 check, tools/check.sh)"
if PATH="$PWD/build/bin:$PATH" lune run tools/guard mac-workflows; then
	echo "ok: none starts from a pull request"
else
	failed=1
fi

exit "$failed"
