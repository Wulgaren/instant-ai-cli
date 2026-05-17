#!/bin/bash

# Shell script to ask AI questions using Cursor CLI
# Usage:
#   ./ask-cursor.sh                    # prompts for your question (type freely, Enter to send)
#   ./ask-cursor.sh word1 word2 ...   # same as before: words joined into one prompt
#   echo question | ./ask-cursor.sh   # read prompt from stdin when not a TTY
#
# Setup:
#   1. Install Cursor CLI: https://cursor.com/docs/cli/headless
#   2. Make sure Cursor CLI is in your PATH
#   3. chmod +x ask-cursor.sh

# Check if agent command is available
if ! command -v agent &> /dev/null; then
    echo "Error: Cursor CLI (agent) not found" >&2
    echo "" >&2
    echo "Please install Cursor CLI:" >&2
    echo "  Visit: https://cursor.com/docs/cli/headless" >&2
    exit 1
fi

# Parse arguments
QUESTION_PARTS=()

while [[ $# -gt 0 ]]; do
    QUESTION_PARTS+=("$1")
    shift
done

# Combine all question parts into a single sentence
QUESTION="${QUESTION_PARTS[*]}"

# No argv: read prompt interactively or from stdin (no shell quoting needed)
if [ -z "$QUESTION" ]; then
    if [ -t 0 ]; then
        read -r -p "Question: " QUESTION || exit 1
    else
        IFS= read -r QUESTION || true
    fi
fi

if [ -z "$QUESTION" ]; then
    echo "Usage: $0 [word1 word2 ...]  or run with no args to type a question" >&2
    exit 1
fi

# System instructions for the AI
SYSTEM_INSTRUCTION="You are a terminal CLI assistant. Provide concise, direct answers suitable for command-line output. Be brief and to the point. Format responses as plain text without markdown. Do not indent lines or use leading whitespace for structure. Use flat lists with dashes at the start of the line. Focus on actionable information. Answer with detail if the reply is short."

# Build the full prompt with system instruction
FULL_PROMPT="${SYSTEM_INSTRUCTION}

User question: ${QUESTION}"

# Strip markdown formatting from one line (plain-text terminal output).
strip_markdown_line() {
    printf "%s" "$1" | sed -E \
        -e 's/^[[:space:]]+//' \
        -e 's/^#{1,6}[[:space:]]+//' \
        -e 's/^```.*$//' \
        -e 's/`([^`]*)`/\1/g' \
        -e 's/\*\*\*([^*]+)\*\*\*/\1/g' \
        -e 's/\*\*([^*]+)\*\*/\1/g' \
        -e 's/\*([^*]+)\*/\1/g' \
        -e 's/\[([^]]+)\]\([^)]+\)/\1/g' \
        -e 's/^>[[:space:]]*//' \
        -e 's/^[-*_]{3,}$//' \
        -e 's/[[:space:]]+$//' \
        2>/dev/null || printf "%s" "$1"
}

strip_stdout_lines() {
    while IFS= read -r raw || [ -n "$raw" ]; do
        line="${raw%$'\r'}"
        stripped=$(strip_markdown_line "$line")
        printf '%s\n' "$stripped"
    done
}

agent --mode=ask -p --model auto "$FULL_PROMPT" | strip_stdout_lines
EXIT_CODE=${PIPESTATUS[0]}

if [ "$EXIT_CODE" -ne 0 ]; then
    echo "" >&2
    echo "Error: Cursor CLI command failed with exit code $EXIT_CODE" >&2
fi

exit "$EXIT_CODE"
