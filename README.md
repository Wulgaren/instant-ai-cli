# Instant AI CLI

A simple shell script to interact with Google's Gemini AI directly from your terminal. Get quick, concise answers without opening a browser or GUI.

## Features

- 🚀 Fast command-line AI assistant
- 🔒 Secure API key storage via macOS Keychain
- 🌐 Optional Google Search grounding for real-time information
- 📝 Concise, terminal-friendly responses
- 🐍 Automatic JSON handling (Python or fallback)

## Prerequisites

- macOS (for Keychain support) or Linux/Unix
- `curl` (usually pre-installed)
- `python3` (optional, for better JSON handling) or `jq` (optional, for JSON parsing)
- Google Gemini API key ([Get one here](https://makersuite.google.com/app/apikey))

## Installation

1. Clone or download this repository
2. Make the script executable:
   ```bash
   chmod +x ask-ai.sh
   ```

## Setup API Key

You have two options for storing your Gemini API key:

### Option 1: macOS Keychain (Recommended)

Store your API key securely in macOS Keychain:

```bash
security add-generic-password -a "gemini-api-key" -s "gemini-api" -w "your-api-key-here" -U
```

The script will automatically retrieve the key from Keychain when needed.

**To view the stored key:**
```bash
security find-generic-password -a "gemini-api-key" -s "gemini-api" -w
```

**To delete the stored key:**
```bash
security delete-generic-password -a "gemini-api-key" -s "gemini-api"
```

### Option 2: Environment Variable

Set the `GEMINI_API_KEY` environment variable:

```bash
export GEMINI_API_KEY='your-api-key-here'
```

To make it persistent, add it to your `~/.zshrc` or `~/.bashrc`:
```bash
echo 'export GEMINI_API_KEY="your-api-key-here"' >> ~/.zshrc
source ~/.zshrc
```

**Note:** The script will try Keychain first (on macOS), then fall back to the environment variable.

## Usage

### Basic Usage

```bash
./ask-ai.sh "your question here"
```

### With Search Grounding

Enable Google Search grounding to get real-time information:

```bash
./ask-ai.sh --grounding "What's the weather in San Francisco today?"
# or use the short flag
./ask-ai.sh -g "What's the weather in San Francisco today?"
```

## Examples

```bash
# Simple question
./ask-ai.sh "How do I list files in a directory?"

# Code-related question
./ask-ai.sh "How do I reverse a string in Python?"

# Real-time information with grounding
./ask-ai.sh -g "What are the latest news about AI?"

# Technical question
./ask-ai.sh "Explain how HTTP requests work"
```

## Options

- `-g, --grounding`: Enable Google Search grounding for real-time information retrieval

## How It Works

1. The script sends your question to Google's Gemini 2.5 Flash model
2. It includes system instructions to provide concise, terminal-friendly answers
3. Optionally uses Google Search grounding for real-time information
4. Returns plain text responses suitable for command-line output

## Model

The script uses **Gemini 2.5 Flash** by default, which provides fast and efficient responses.

## Troubleshooting

### "API request failed" error

- Verify your API key is correct
- Check that you have internet connectivity
- Ensure your API key has the necessary permissions

### "GEMINI_API_KEY not found" error

- Make sure you've set up the API key using one of the methods above
- On macOS, verify the keychain entry exists:
  ```bash
  security find-generic-password -a "gemini-api-key" -s "gemini-api"
  ```

### JSON parsing issues

- Install `python3` for better JSON handling, or
- Install `jq` for JSON parsing: `brew install jq` (macOS) or `sudo apt-get install jq` (Linux)

## License

This project is open source and available for personal use.

## Contributing

Feel free to submit issues or pull requests if you have improvements!
