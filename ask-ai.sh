#!/bin/bash

# Shell script to ask AI questions and get text responses using Gemini API
# Usage: ./ask-ai.sh [-g|--grounding] word1 word2 word3 ...
#
# Options:
#   -g, --grounding    Enable Google Search grounding for real-time information
#
# Note: All words after the script name (except flags) will be combined into a single sentence
#
# Setup:
#   Option 1 (Recommended): Store in macOS Keychain
#     security add-generic-password -a "gemini-api-key" -s "gemini-api" -w "your-api-key-here" -U
#   Option 2: Use environment variable
#     export GEMINI_API_KEY='your-api-key-here'
#   chmod +x ask-ai.sh

# Try to get API key from macOS Keychain first, then fall back to environment variable
API_KEY=""

# Check macOS Keychain (only on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    KEYCHAIN_KEY=$(security find-generic-password -a "gemini-api-key" -s "gemini-api" -w 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$KEYCHAIN_KEY" ]; then
        API_KEY="$KEYCHAIN_KEY"
    fi
fi

# Fall back to environment variable if keychain didn't work
if [ -z "$API_KEY" ] && [ -n "${GEMINI_API_KEY:-}" ]; then
    API_KEY="${GEMINI_API_KEY}"
fi

# Use API_KEY for the rest of the script
GEMINI_API_KEY="$API_KEY"

# Check if API key is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY not found" >&2
    echo "" >&2
    echo "Please set it using one of these methods:" >&2
    echo "" >&2
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  Option 1 (Recommended - macOS Keychain):" >&2
        echo "    security add-generic-password -a \"gemini-api-key\" -s \"gemini-api\" -w \"your-api-key-here\" -U" >&2
        echo "" >&2
    fi
    echo "  Option 2 (Environment variable):" >&2
    echo "    export GEMINI_API_KEY='your-api-key-here'" >&2
    exit 1
fi

# Parse arguments
ENABLE_GROUNDING=false
QUESTION_PARTS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--grounding)
            ENABLE_GROUNDING=true
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
    echo "Usage: $0 [-g|--grounding] word1 word2 word3 ..." >&2
    echo "  -g, --grounding    Enable Google Search grounding for real-time information" >&2
    exit 1
fi

# System instructions for the AI
SYSTEM_INSTRUCTION="You are a terminal CLI assistant. Provide concise, direct answers suitable for command-line output. Be brief and to the point. Format responses as plain text without markdown unless specifically requested. Focus on actionable information. Answer with detail if the reply is short."

# Escape JSON special characters in the question and system instruction
# Use Python if available for proper JSON encoding, otherwise use sed
if command -v python3 &> /dev/null; then
    JSON_PAYLOAD=$(python3 <<PYEOF
import json
import sys

system_instruction = """${SYSTEM_INSTRUCTION}"""
question = """${QUESTION}"""
enable_grounding = "${ENABLE_GROUNDING}" == "true"

full_prompt = f"{system_instruction}\n\nUser question: {question}"

payload = {
    "contents": [{
        "parts": [{
            "text": full_prompt
        }]
    }]
}

# Add grounding via tools if enabled
if enable_grounding:
    payload["tools"] = [{
        "googleSearch": {}
    }]

print(json.dumps(payload))
PYEOF
)
else
    # Fallback: manual escaping (less robust but works for simple cases)
    ESCAPED_QUESTION=$(echo "$QUESTION" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    ESCAPED_INSTRUCTION=$(echo "$SYSTEM_INSTRUCTION" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    
    if [ "$ENABLE_GROUNDING" = true ]; then
        JSON_PAYLOAD=$(cat <<EOF
{
  "contents": [{
    "parts": [{
      "text": "${ESCAPED_INSTRUCTION}\n\nUser question: ${ESCAPED_QUESTION}"
    }]
  }],
  "tools": [{
    "googleSearch": {}
  }]
}
EOF
)
    else
        JSON_PAYLOAD=$(cat <<EOF
{
  "contents": [{
    "parts": [{
      "text": "${ESCAPED_INSTRUCTION}\n\nUser question: ${ESCAPED_QUESTION}"
    }]
  }]
}
EOF
)
    fi
fi

# Use Gemini 2.5 Flash
MODEL="gemini-2.5-flash"
API_VERSION="v1beta"

# Make API request to Gemini
API_URL="https://generativelanguage.googleapis.com/${API_VERSION}/models/${MODEL}:generateContent?key=${GEMINI_API_KEY}"
RESPONSE=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD")

# Check if request was successful
if echo "$RESPONSE" | grep -q '"error"'; then
    echo "Error: API request failed" >&2
    echo "Model: ${MODEL}" >&2
    echo "API Version: ${API_VERSION}" >&2
    if command -v jq &> /dev/null; then
        echo "$RESPONSE" | jq '.' >&2
    else
        echo "$RESPONSE" >&2
    fi
    exit 1
fi

# Extract text response - try using jq if available, otherwise use sed
if command -v jq &> /dev/null; then
    echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text' 2>/dev/null
else
    # Fallback: extract text using sed (handles escaped quotes and newlines)
    echo "$RESPONSE" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p' | sed 's/\\n/\n/g' | sed 's/\\"/"/g' | sed 's/\\\\/\\/g'
fi
