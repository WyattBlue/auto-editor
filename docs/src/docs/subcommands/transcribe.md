---
title: transcribe
---

## transcribe
`transcribe` transcribes the audio of a media file using cloud AI APIs (Groq, OpenAI, Gemini). It is useful for generating subtitles, creating transcripts, detecting topic boundaries, and summarizing content in video files.

Usage:
```
auto-editor transcribe <file> [options]
```

Examples:
```
# Basic transcription with Groq (default)
auto-editor transcribe example.mp4

# Transcribe Turkish content
auto-editor transcribe example.mp4 --language tr

# Transcribe to SRT format
auto-editor transcribe example.mp4 --format srt -o output.srt

# Detect topic boundaries in Turkish content
auto-editor transcribe example.mp4 --language tr --detect-topics

# Summarize Turkish content
auto-editor transcribe example.mp4 --language tr --summarize

# Use OpenAI instead of Groq
auto-editor transcribe example.mp4 --provider openai

# Use Gemini with topic detection
auto-editor transcribe example.mp4 --provider gemini --detect-topics

# Summarize with Gemini
auto-editor transcribe example.mp4 --provider gemini --summarize
```

## Options

### `<file>`
The input media file. Only the first audio stream is used; the audio is extracted to MP3 format before sending to the API.

### `--provider PROVIDER`
Choose the AI provider for transcription. Choices are `groq`, `openai`, and `gemini`. (default `groq`)

### `--api-key KEY`
API key for the chosen provider. If not provided, the tool will look for environment variables: `GROQ_API_KEY`, `OPENAI_API_KEY`, or `GEMINI_API_KEY`.

### `--model MODEL`
Override the default model for the provider:
- Groq: `whisper-large-v3` (default)
- OpenAI: `whisper-1` (default)
- Gemini: `gemini-1.5-flash` (default)

### `--chat-model MODEL`
Chat model used for topic detection and summarization with Groq/OpenAI providers. Defaults:
- Groq: `llama-3.3-70b-versatile`
- OpenAI: `gpt-4o-mini`

### `-l, --language LANG`
Set the spoken language code. Examples: `tr`, `en`, `ja`. Use `tr` for Turkish content. (default `auto`)

### `-f, --format FORMAT`
Output format. Choices are `srt`, `text`, and `json`. (default `srt`)

When using `--detect-topics`, the output format is automatically set to `json`.

### `-o, --output FILE`
Where to write the output. (defaults to stdout)

### `--detect-topics`
Detect topic boundaries in the audio and return them as JSON timestamps. This feature works best with Turkish content when using `--language tr`.

Output format (JSON):
```json
{
  "topics": [
    { "start": "HH:MM:SS", "end": "HH:MM:SS", "title": "Topic title" }
  ]
}
```

When using `--format srt`, the topic detection output is automatically converted to SRT subtitle format:
```
1
00:00:00 --> 00:05:00
Introduction

2
00:05:00 --> 00:10:00
Main Content
```

This allows you to use topic detection results as subtitles that can be imported into video editors.

### `--summarize`
Generate a summary of the audio content. This feature works best with Turkish content when using `--language tr`.

Output format:
```json
{
  "summary": "General summary text",
  "key_points": ["Key point 1", "Key point 2", "Key point 3"],
  "speaker_intent": "Speaker's purpose or message",
  "conclusion": "Conclusion or recommendations (if any)"
}
```

When using `--summarize`, the output format is automatically set to `json`. The summary is formatted as pretty-printed JSON for better readability.

## Turkish Content Support

The `transcribe` command has special support for Turkish content:

- **Language Detection**: Use `--language tr` or `--language tur` to indicate Turkish audio
- **Topic Detection**: `--detect-topics` works particularly well with Turkish content
- **Summarization**: `--summarize` works particularly well with Turkish content
- **Native Prompts**: The tool uses Turkish prompts for better accuracy with Turkish content

Example Turkish workflow:
```
# Transcribe Turkish video to SRT subtitles
auto-editor transcribe turkish_video.mp4 --language tr --format srt -o subtitles.srt

# Detect topics in Turkish lecture as SRT subtitles
auto-editor transcribe lecture.mp4 --language tr --detect-topics --format srt -o topics.srt

# Detect topics in Turkish lecture as JSON
auto-editor transcribe lecture.mp4 --language tr --detect-topics -o topics.json

# Summarize Turkish content
auto-editor transcribe lecture.mp4 --language tr --summarize -o summary.json
```

## Provider-Specific Notes

### Groq
- Fast transcription with Whisper large-v3
- Free tier available with rate limits
- Good for Turkish content

### OpenAI
- High quality transcription
- Pay-per-use pricing
- Excellent multilingual support

### Gemini
- Single-step transcription and topic detection
- Can process audio directly without separate transcription step
- Good for combined workflows

## Environment Variables

Set your API key as an environment variable:
```bash
export GROQ_API_KEY="your-groq-api-key"
export OPENAI_API_KEY="your-openai-api-key"
export GEMINI_API_KEY="your-gemini-api-key"
```

---
### Notes
- The tool requires an internet connection to access cloud APIs
- Audio is extracted to MP3 format before processing
- Large files may take longer to process depending on the provider
- Topic detection uses additional API calls with chat models
