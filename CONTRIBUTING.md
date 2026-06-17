# Contributing

Wisp is intentionally small. Contributions should keep the app easy to build, easy to understand, and reliable for everyday dictation.

## Local Setup

```bash
./scripts/setup_whisper.sh
swift build -c release
./scripts/build_app.sh
```

## Guidelines

- Keep native macOS behavior simple and predictable.
- Prefer one final insertion over live partial text edits.
- Keep Dictate local by default.
- Make Compose optional and explicit because it sends transcript text to OpenAI.
- Do not commit API keys, generated app bundles, local model caches, or machine-specific files.

## Before Opening A PR

Run:

```bash
swift build -c release
python3 -m py_compile Sources/Wisp/Resources/stream_transcribe.py
```
