#!/bin/bash

# Shell script to ask AI questions using Cursor CLI
# Usage: ./ask-cursor.sh word1 word2 word3 ...
#
# Note: All words after the script name will be combined into a single sentence
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

# Check if question is provided
if [ -z "$QUESTION" ]; then
    echo "Usage: $0 word1 word2 word3 ..." >&2
    exit 1
fi

# System instructions for the AI
SYSTEM_INSTRUCTION="You are a terminal CLI assistant. Provide concise, direct answers suitable for command-line output. Be brief and to the point. Format responses as plain text without markdown unless specifically requested. Focus on actionable information. Answer with detail if the reply is short."

# Build the full prompt with system instruction
FULL_PROMPT="${SYSTEM_INSTRUCTION}

User question: ${QUESTION}"

# Use Cursor CLI with streaming output
# --output-format stream-json provides message-level progress tracking
# --stream-partial-output provides incremental streaming of deltas
# Process the JSON stream to extract and display content incrementally

# Track accumulated output to avoid duplicates
# Use a temp file to persist state across the pipe subshell
TEMP_STATE=$(mktemp)
TEMP_THINKING=$(mktemp)
trap "rm -f $TEMP_STATE $TEMP_THINKING" EXIT
echo -n "" > "$TEMP_STATE"

# Shown when content type is "thinking"; cleared when first text arrives
THINKING_MSG="Thinking... "

# Function to strip markdown formatting from text
# Uses pandoc if available (best), otherwise uses sed-based stripping
strip_markdown() {
    local text="$1"
    
    if command -v pandoc &> /dev/null; then
        # Use pandoc to convert markdown to plain text (best option)
        echo -n "$text" | pandoc -f markdown -t plain --wrap=none 2>/dev/null || echo -n "$text"
    else
        # Fallback: sed-based markdown stripping (BSD sed compatible)
        # Focus on inline markdown that works with streaming deltas
        local result="$text"
        
        # Remove code blocks (```code```) - greedy match
        result=$(printf "%s" "$result" | sed -E 's/```[^`]*```//g' 2>/dev/null || printf "%s" "$result")
        
        # Remove inline code (`code`)
        result=$(printf "%s" "$result" | sed -E 's/`([^`]*)`/\1/g' 2>/dev/null || printf "%s" "$result")
        
        # Remove bold/italic: **text**, *text*, __text__, _text_
        # Handle bold first (more specific), then italic
        result=$(printf "%s" "$result" | sed -E 's/\*\*([^*]+)\*\*/\1/g' 2>/dev/null || printf "%s" "$result")
        result=$(printf "%s" "$result" | sed -E 's/__([^_]+)__/\1/g' 2>/dev/null || printf "%s" "$result")
        result=$(printf "%s" "$result" | sed -E 's/\*([^*]+)\*/\1/g' 2>/dev/null || printf "%s" "$result")
        result=$(printf "%s" "$result" | sed -E 's/_([^_]+)_/\1/g' 2>/dev/null || printf "%s" "$result")
        
        # Remove links: [text](url) -> text
        result=$(printf "%s" "$result" | sed -E 's/\[([^\]]+)\]\([^)]+\)/\1/g' 2>/dev/null || printf "%s" "$result")
        
        # Remove table separators: | (but keep content)
        result=$(printf "%s" "$result" | sed -E 's/\|/ /g' 2>/dev/null || printf "%s" "$result")
        
        # Note: Line-based markdown (headers, lists, blockquotes) are harder to strip
        # in streaming mode, but the AI is instructed to avoid markdown anyway
        
        printf "%s" "$result"
    fi
}

# Function to process each line of the stream
process_line() {
    local line="$1"
    
    # Check for errors in the line
    if echo "$line" | grep -q '"error"'; then
        echo "Error: $(echo "$line" | jq -r '.error.message // .error' 2>/dev/null || echo "$line")" >&2
        return
    fi
    
    # Skip empty lines
    [ -z "$line" ] && return
    
    # Parse JSON stream - Cursor CLI outputs JSON objects on each line
    # Format matches: {"type":"assistant","message":{"content":[{"text":"..."}]}}
    if command -v jq &> /dev/null; then
        # Extract type and subtype
        type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        subtype=$(echo "$line" | jq -r '.subtype // empty' 2>/dev/null)
        
        # If jq failed, the line might not be valid JSON - skip it
        if [ $? -ne 0 ] || [ -z "$type" ]; then
            return
        fi
        
        # Handle assistant messages with text content or thinking indicator
        if [ "$type" = "assistant" ]; then
            content_type=$(echo "$line" | jq -r '.message.content[0].type // "text"' 2>/dev/null)
            if [ "$content_type" = "thinking" ]; then
                # Show "Thinking... " once, then stay on same line until text arrives
                if [ ! -s "$TEMP_THINKING" ]; then
                    printf "%s\r" "$THINKING_MSG"
                    echo -n "1" > "$TEMP_THINKING"
                fi
                return
            fi
            # Clear thinking indicator if it was shown, before outputting text
            if [ -s "$TEMP_THINKING" ]; then
                printf '\r%*s\r' ${#THINKING_MSG} ""
                rm -f "$TEMP_THINKING"
            fi
            # Extract text from message.content[0].text
            # The stream sends incremental deltas (new text only)
            content=$(echo "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null)
            
            if [ -n "$content" ] && [ "$content" != "null" ] && [ "$content" != "" ]; then
                # Read what we've already output (accumulated so far)
                already_output=$(cat "$TEMP_STATE" 2>/dev/null || echo "")
                
                # Check if this content is new
                if [ "$content" != "$already_output" ]; then
                    # If content is longer and starts with what we've already output,
                    # it's accumulated text - extract only the new suffix
                    if [ "${#content}" -gt "${#already_output}" ] && [ -n "$already_output" ] && [ "${content#$already_output}" != "$content" ]; then
                        # Content is accumulated: already_output + new_part
                        new_content="${content#$already_output}"
                        # Strip markdown from the new content before outputting
                        stripped_content=$(strip_markdown "$new_content")
                        printf "%s" "$stripped_content"
                        echo -n "$content" > "$TEMP_STATE"
                    elif [ -z "$already_output" ] || [ "${content#$already_output}" = "$content" ]; then
                        # Content is either:
                        # 1. First content (already_output is empty), or
                        # 2. Completely different (doesn't start with already_output)
                        # Treat as new delta and append
                        # Strip markdown from the content before outputting
                        stripped_content=$(strip_markdown "$content")
                        printf "%s" "$stripped_content"
                        echo -n "${already_output}${content}" > "$TEMP_STATE"
                    fi
                    # If content exactly matches already_output, skip (duplicate)
                fi
            fi
        fi
    else
        # Fallback: extract text using sed/grep
        if echo "$line" | grep -q '"type"\s*:\s*"assistant"'; then
            # If this line is thinking content, show indicator and skip
            if echo "$line" | grep -q '"type"\s*:\s*"thinking"'; then
                if [ ! -s "$TEMP_THINKING" ]; then
                    printf "%s\r" "$THINKING_MSG"
                    echo -n "1" > "$TEMP_THINKING"
                fi
                return
            fi
            if [ -s "$TEMP_THINKING" ]; then
                printf '\r%*s\r' ${#THINKING_MSG} ""
                rm -f "$TEMP_THINKING"
            fi
            # Try to extract text from message.content[0].text
            CONTENT=$(echo "$line" | sed -E 's/.*"text"\s*:\s*"(([^"\\]|\\.)*)".*/\1/' 2>/dev/null)
            
            if [ -n "$CONTENT" ] && [ "$CONTENT" != "$line" ]; then
                # Unescape common JSON escape sequences
                UNESCAPED=$(printf "%s" "$CONTENT" | sed \
                    -e 's/\\n/\n/g' \
                    -e 's/\\"/"/g' \
                    -e 's/\\\\/\\/g' \
                    -e 's/\\t/\t/g' \
                    -e 's/\\r/\r/g')
                
                # Read what we've already output (accumulated so far)
                already_output=$(cat "$TEMP_STATE" 2>/dev/null || echo "")
                
                # Only output if different
                if [ "$UNESCAPED" != "$already_output" ]; then
                    # If content is longer and starts with what we've already output, extract new part
                    if [ "${#UNESCAPED}" -gt "${#already_output}" ] && [ -n "$already_output" ] && [ "${UNESCAPED#$already_output}" != "$UNESCAPED" ]; then
                        new_content="${UNESCAPED#$already_output}"
                        # Strip markdown from the new content before outputting
                        stripped_content=$(strip_markdown "$new_content")
                        printf "%s" "$stripped_content"
                        echo -n "$UNESCAPED" > "$TEMP_STATE"
                    elif [ -z "$already_output" ] || [ "${UNESCAPED#$already_output}" = "$UNESCAPED" ]; then
                        # New delta - append to accumulated
                        # Strip markdown from the content before outputting
                        stripped_content=$(strip_markdown "$UNESCAPED")
                        printf "%s" "$stripped_content"
                        echo -n "${already_output}${UNESCAPED}" > "$TEMP_STATE"
                    fi
                fi
            fi
        fi
    fi
}

# Process the stream with unbuffered output for real-time streaming
# On Linux: stdbuf -oL -eL disables pipe buffering. On macOS (no stdbuf): use script -q to run agent with a pty so it line-buffers.
if command -v stdbuf &> /dev/null; then
    stdbuf -oL -eL agent --mode=ask -p --force --output-format stream-json --stream-partial-output "$FULL_PROMPT" 2>&1 | while IFS= read -r line; do
        process_line "$line"
    done
else
    # macOS and others without stdbuf: run agent with a pty via script so stdout is line-buffered and stream appears in real time
    if command -v script &> /dev/null; then
        script -q /dev/null agent --mode=ask -p --force --output-format stream-json --stream-partial-output "$FULL_PROMPT" 2>/dev/null | while IFS= read -r line; do
            process_line "$line"
        done
    else
        agent --mode=ask -p --force --output-format stream-json --stream-partial-output "$FULL_PROMPT" 2>&1 | while IFS= read -r line; do
            process_line "$line"
        done
    fi
fi

# Check exit status
EXIT_CODE=${PIPESTATUS[0]}
if [ $EXIT_CODE -ne 0 ]; then
    echo "Error: Cursor CLI command failed with exit code $EXIT_CODE" >&2
    exit $EXIT_CODE
fi

# Add newline at the end
echo
