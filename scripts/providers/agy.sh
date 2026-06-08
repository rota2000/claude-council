#!/bin/bash
# ABOUTME: Queries the Google Antigravity CLI (agy) in headless print mode using subscription auth
# ABOUTME: Availability is gated on the agy binary being on PATH, not an API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/verbosity.sh"
source "$SCRIPT_DIR/../lib/providers.sh"

verbosity_prefix VERBOSITY_PREFIX "${COUNCIL_VERBOSITY:-standard}"

PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo "Error: No prompt provided" >&2
    exit 1
fi

if ! command -v agy >/dev/null 2>&1; then
    echo "Error: agy CLI not found on PATH" >&2
    exit 1
fi

SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"
FULL_PROMPT="${SYSTEM}

${PROMPT}"

# agy is an agentic CLI that can run tools and touch the filesystem. We do NOT
# pass --dangerously-skip-permissions: the council prompt can carry attacker-
# influenceable content (auto-context injects repo file bodies), and auto-approving
# every tool request would let an injected instruction execute commands in the
# user's repo. A read-only advisory query needs no tools, so plain --print is the
# safe default — any tool attempt is left un-approved rather than auto-run. This is
# a stronger guard than codex's --skip-git-repo-check / gemini-cli's --skip-trust,
# which only bypass a launch/trust gate, not per-action approval.
#
# We also deliberately do NOT pass -m/--model: Antigravity is a multi-model agent
# and uses whatever model it is configured with. get_model agy therefore reports
# "default" for the cache key / pane header.
ARGS=(--print "$FULL_PROMPT")

ERR_TMP=$(mktemp)
trap 'rm -f "$ERR_TMP"' EXIT

if ! RESPONSE=$(agy "${ARGS[@]}" 2>"$ERR_TMP"); then
    ERR_MSG=$(tr '\n' ' ' < "$ERR_TMP" | head -c 500)
    echo "Error from agy CLI: ${ERR_MSG:-non-zero exit}" >&2
    exit 1
fi

# agy reports print-mode failures (notably timeouts) as an "Error: ..." line on
# STDOUT with a zero exit code — unlike codex/gemini-cli, which exit non-zero.
# Guard against that so the council never serves (and caches) a CLI error as a
# real answer.
if [[ -z "$RESPONSE" || "$RESPONSE" == "Error: timed out waiting for response"* ]]; then
    echo "Error from agy CLI: ${RESPONSE:-empty response}" >&2
    exit 1
fi

echo "$RESPONSE"
