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

# agy is an agentic CLI that can run tools and touch the filesystem. We pass
# --dangerously-skip-permissions so agy can READ repo files referenced by a query
# without an interactive approval prompt — headless --print has no other way to
# approve a tool request, so plain --print leaves agy with no filesystem access.
#
# SECURITY TRADEOFF (deliberately accepted): --dangerously-skip-permissions auto-
# approves ALL tool requests — read, WRITE, and terminal/command execution, not just
# reads (agy exposes no read-only mode). The council prompt can carry attacker-
# influenceable content (auto-context injects repo file bodies), so an injected
# instruction could make agy read a secret and echo it into its (cached) response,
# or run a command / write a file in the repo. Only query agy on trusted content.
#
# We deliberately do NOT pass -m/--model: Antigravity is a multi-model agent and
# uses whatever model it is configured with. get_model agy therefore reports
# "default" for the cache key / pane header.
ARGS=(--print --dangerously-skip-permissions "$FULL_PROMPT")

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
