#!/bin/bash

# Shell script to ask AI questions and get streaming text responses using Groq API
# Usage: ./ask-groq.sh [-g|--grounding] [-t|--thinking] word1 word2 word3 ...
#
# Options:
#   -g, --grounding    Enable web search grounding for real-time information
#   -t, --thinking     Enable thinking mode using kimi-k2 model
#
# Note: All words after the script name (except flags) will be combined into a single sentence
#
# Setup:
#   Option 1 (Recommended): Store in macOS Keychain
#     security add-generic-password -a "groq-api-key" -s "groq-api" -w "your-api-key-here" -U
#   Option 2: Use environment variable
#     export GROQ_API_KEY='your-api-key-here'
#   chmod +x ask-groq.sh

# Try to get API key from macOS Keychain first, then fall back to environment variable
API_KEY=""

# Check macOS Keychain (only on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    KEYCHAIN_KEY=$(security find-generic-password -a "groq-api-key" -s "groq-api" -w 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$KEYCHAIN_KEY" ]; then
        API_KEY="$KEYCHAIN_KEY"
    fi
fi

# Fall back to environment variable if keychain didn't work
if [ -z "$API_KEY" ] && [ -n "${GROQ_API_KEY:-}" ]; then
    API_KEY="${GROQ_API_KEY}"
fi

# Check if API key is set
if [ -z "$API_KEY" ]; then
    echo "Error: GROQ_API_KEY not found" >&2
    echo "" >&2
    echo "Please set it using one of these methods:" >&2
    echo "" >&2
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  Option 1 (Recommended - macOS Keychain):" >&2
        echo "    security add-generic-password -a \"groq-api-key\" -s \"groq-api\" -w \"your-api-key-here\" -U" >&2
        echo "" >&2
    fi
    echo "  Option 2 (Environment variable):" >&2
    echo "    export GROQ_API_KEY='your-api-key-here'" >&2
    exit 1
fi

# Parse arguments
ENABLE_GROUNDING=false
ENABLE_THINKING=false
QUESTION_PARTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--grounding)
            ENABLE_GROUNDING=true
            shift
            ;;
        -t|--thinking)
            ENABLE_THINKING=true
            shift
            ;;
        *)
            QUESTION_PARTS+=("$1")
            shift
            ;;
    esac
done

# Combine all question parts into a single sentence
QUESTION="${QUESTION_PARTS[*]}"

# Check if question is provided
if [ -z "$QUESTION" ]; then
    echo "Usage: $0 [-g|--grounding] [-t|--thinking] word1 word2 word3 ..." >&2
    echo "  -g, --grounding    Enable web search grounding for real-time information" >&2
    echo "  -t, --thinking     Enable thinking mode using kimi-k2 model" >&2
    exit 1
fi

# System instructions for the AI
SYSTEM_INSTRUCTION="You are a terminal CLI assistant. Provide concise, direct answers suitable for command-line output. Be brief and to the point. NEVER use markdown formatting - no asterisks, no bold, no headers, no bullet points with dashes. Use plain text only with simple line breaks for structure. Focus on actionable information."

# Select model based on options
# compound-beta supports web search tool use
# moonshotai/kimi-k2-instruct-0905 supports thinking mode
if [ "$ENABLE_THINKING" = true ]; then
    MODEL="moonshotai/kimi-k2-instruct-0905"
elif [ "$ENABLE_GROUNDING" = true ]; then
    MODEL="compound-beta"
else
    MODEL="llama-3.1-8b-instant"
fi

# Build JSON payload using Python for proper escaping
if command -v python3 &> /dev/null; then
    JSON_PAYLOAD=$(python3 <<PYEOF
import json

system_instruction = """${SYSTEM_INSTRUCTION}"""
question = """${QUESTION}"""
enable_grounding = "${ENABLE_GROUNDING}" == "true"
enable_thinking = "${ENABLE_THINKING}" == "true"
model = "${MODEL}"

payload = {
    "model": model,
    "messages": [
        {
            "role": "system",
            "content": system_instruction
        },
        {
            "role": "user",
            "content": question
        }
    ],
    "stream": True
}

# Note: kimi-k2 doesn't support reasoning_format, but we use it when thinking is enabled
# The model will work normally without special parameters

print(json.dumps(payload))
PYEOF
)
else
    # Fallback: manual escaping
    ESCAPED_QUESTION=$(echo "$QUESTION" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    ESCAPED_INSTRUCTION=$(echo "$SYSTEM_INSTRUCTION" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Build JSON payload - kimi-k2 doesn't need special parameters
    if [ "$ENABLE_THINKING" = true ]; then
        JSON_PAYLOAD=$(cat <<EOF
{
  "model": "${MODEL}",
  "messages": [
    {
      "role": "system",
      "content": "${ESCAPED_INSTRUCTION}"
    },
    {
      "role": "user",
      "content": "${ESCAPED_QUESTION}"
    }
  ],
  "stream": true
}
EOF
)
    else
        JSON_PAYLOAD=$(cat <<EOF
{
  "model": "${MODEL}",
  "messages": [
    {
      "role": "system",
      "content": "${ESCAPED_INSTRUCTION}"
    },
    {
      "role": "user",
      "content": "${ESCAPED_QUESTION}"
    }
  ],
  "stream": true
}
EOF
)
    fi
fi

# Make streaming API request to Groq
API_URL="https://api.groq.com/openai/v1/chat/completions"

# Stream the response and parse SSE data using Python for proper handling
# Capture stderr to check for errors
ERROR_OUTPUT=$(mktemp)
trap "rm -f $ERROR_OUTPUT" EXIT

curl -sN -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d "$JSON_PAYLOAD" 2>"$ERROR_OUTPUT" | python3 -u -c "
import sys
import json
import os

# Force unbuffered stdin
sys.stdin = os.fdopen(sys.stdin.fileno(), 'r', buffering=1)

error_occurred = False
while True:
    line = sys.stdin.readline()
    if not line:
        break
    line = line.strip()
    if not line:
        continue
    if line.startswith('data: '):
        json_str = line[6:]
        if json_str == '[DONE]':
            print()
            break
        try:
            data = json.loads(json_str)
            # Check for errors in the response
            if 'error' in data:
                print(f\"Error: {data.get('error', {}).get('message', 'Unknown error')}\", file=sys.stderr)
                error_occurred = True
                break
            # Extract content from delta
            delta = data.get('choices', [{}])[0].get('delta', {})
            content = delta.get('content', '')
            if content:
                print(content, end='', flush=True)
        except json.JSONDecodeError as e:
            # If we can't parse JSON, it might be an error message
            if json_str and not json_str.startswith('{'):
                pass  # Skip non-JSON lines
            else:
                print(f\"JSON parse error: {e}\", file=sys.stderr)
                error_occurred = True
                break

if error_occurred:
    sys.exit(1)
" || {
    # If curl or Python failed, show error output
    if [ -s "$ERROR_OUTPUT" ]; then
        echo "Error details:" >&2
        cat "$ERROR_OUTPUT" >&2
    fi
    exit 1
}
