#!/bin/bash

# Shell script to ask AI questions using Ollama with qwen3:8b
# Usage: ./ask-ollama.sh [-w|--web-search] word1 word2 word3 ...
#
# Options:
#   -w, --web-search    Enable web search for real-time information
#
# Note: All words after the script name (except flags) will be combined into a single sentence
#
# Setup:
#   1. Install Ollama: https://ollama.ai
#   2. Pull the qwen3:8b model: ollama pull qwen3:8b
#   3. Make sure Ollama is running (it should start automatically)
#   4. chmod +x ask-ollama.sh

MODEL="qwen3:4b"

# Parse arguments
ENABLE_WEB_SEARCH=false
QUESTION_PARTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--web-search)
            ENABLE_WEB_SEARCH=true
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
    echo "Usage: $0 [-w|--web-search] word1 word2 word3 ..." >&2
    echo "  -w, --web-search    Enable web search for real-time information" >&2
    exit 1
fi

# System instructions for the AI
SYSTEM_INSTRUCTION="You are a terminal CLI assistant. Provide concise, direct answers suitable for command-line output. Be brief and to the point. Format responses as plain text without markdown unless specifically requested. Focus on actionable information. Answer with detail if the reply is short."

# If web search is not enabled, use ollama run directly (faster)
if [ "$ENABLE_WEB_SEARCH" = false ]; then
    ollama run "${MODEL}" --think=false "${SYSTEM_INSTRUCTION}

${QUESTION}"
    exit 0
fi

# If web search is enabled, use the API
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# Escape JSON special characters
if command -v python3 &> /dev/null; then
    JSON_PAYLOAD=$(python3 <<PYEOF
import json

system_instruction = """${SYSTEM_INSTRUCTION}"""
question = """${QUESTION}"""

payload = {
    "model": "${MODEL}",
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
    "stream": True,
    "options": {
        "think": False,
        "web_search": True
    }
}

print(json.dumps(payload))
PYEOF
)
else
    # Fallback: manual escaping
    ESCAPED_QUESTION=$(echo "$QUESTION" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    ESCAPED_INSTRUCTION=$(echo "$SYSTEM_INSTRUCTION" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
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
  "stream": true,
  "options": {
    "think": false,
    "web_search": true
  }
}
EOF
)
fi

# Make API request to Ollama with streaming
API_URL="${OLLAMA_HOST}/api/chat"

# Process streaming response
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" | while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue
    
    # Extract content from each JSON line (streaming format)
    if command -v jq &> /dev/null; then
        CONTENT=$(echo "$line" | jq -r '.message.content // empty' 2>/dev/null)
        if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
            echo -n "$CONTENT"
        fi
    else
        # Fallback: extract content using sed
        CONTENT=$(echo "$line" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' 2>/dev/null)
        if [ -n "$CONTENT" ]; then
            echo -n "$CONTENT" | sed 's/\\n/\n/g' | sed 's/\\"/"/g' | sed 's/\\\\/\\/g'
        fi
    fi
done

# Add newline at the end
echo
