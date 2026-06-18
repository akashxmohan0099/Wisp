# Wisp

Wisp is a small MacBook/macOS dictation utility that floats above your desktop. Click it, speak, and Wisp inserts the final text into the app you were using.

This repository is the macOS app only. There is no iPhone, iPad, or mobile app target in this repo.

It has two modes:

- **Dictate**: local Whisper transcription with light cleanup.
- **Compose**: local Whisper transcription, then an optional OpenAI rewrite for more polished, paste-ready text.

The app is intentionally simple: native macOS UI, local microphone capture, local transcription by default, and one final paste after recording stops. It does not stream partial text into the active app, which keeps cursor insertion much more reliable.

## Features

- Floating mic bubble that works across spaces.
- Radial hover actions for Dictate and Compose.
- Global shortcuts:
  - `Control + Option + D` starts or stops Dictate.
  - `Control + Option + C` starts or stops Compose.
- Local audio capture with `AVAudioEngine`.
- Local transcription with `faster-whisper`.
- Optional OpenAI compose pass using the Responses API.
- Automatic paste through macOS Accessibility, with clipboard fallback.
- Menu bar controls for permissions, copy, paste, and quit.

## Requirements

- macOS 14 or later.
- Xcode command line tools.
- Python 3.10 or later. Homebrew Python is preferred.
- `ffmpeg` available on `PATH` for testing and some Whisper workflows.
- A local Whisper model. The setup script downloads the default model for you.

## Install From Source

1. Install the basic Mac developer tools:

```bash
xcode-select --install
```

2. Install Homebrew dependencies:

```bash
brew install python ffmpeg
```

3. Clone the repo and install the local Whisper runtime:

```bash
git clone https://github.com/akashxmohan0099/Wisp.git
cd Wisp
./scripts/setup_whisper.sh
```

The setup script creates `~/.wisp/venv`, installs [`faster-whisper`](https://github.com/SYSTRAN/faster-whisper), and downloads the default local model, [`base.en`](https://huggingface.co/Systran/faster-whisper-base.en). The model is stored in your normal Hugging Face cache, not committed to this repo.

4. Build and open the app:

```bash
./scripts/build_app.sh
open dist/Wisp.app
```

The first launch should prompt for microphone access. For automatic insertion into other apps, open the menu bar item and choose **Prompt Accessibility Permission**, then allow Wisp in System Settings.

You can move `dist/Wisp.app` into `/Applications` after building:

```bash
cp -R dist/Wisp.app /Applications/
open /Applications/Wisp.app
```

## Local Whisper Model

Yes, each person running Wisp needs a local Whisper runtime and model on their own Mac. That is what keeps Dictate mode local.

The simplest path is:

```bash
./scripts/setup_whisper.sh
```

By default this downloads `base.en`, which is fast and good enough for quick dictation. To download a different model during setup:

```bash
WISP_MODEL_DOWNLOAD=large-v3-turbo ./scripts/setup_whisper.sh
```

Then run Wisp with the same model:

```bash
export WISP_MODEL="large-v3-turbo"
open dist/Wisp.app
```

Useful links:

- [`faster-whisper` runtime](https://github.com/SYSTRAN/faster-whisper)
- [`base.en` model](https://huggingface.co/Systran/faster-whisper-base.en)
- [`large-v3-turbo` model](https://huggingface.co/Systran/faster-whisper-large-v3-turbo)

## OpenAI Setup For Compose

Dictate mode is local. Compose mode needs an OpenAI API key unless you only want the local cleanup fallback.

Wisp reads the key in this order:

1. `OPENAI_API_KEY`
2. `~/Library/Application Support/Wisp/openai-key`
3. legacy `~/Library/Application Support/Whisp/openai-key`

To save a key locally without exporting it in every shell:

```bash
mkdir -p "$HOME/Library/Application Support/Wisp"
printf "%s\n" "sk-..." > "$HOME/Library/Application Support/Wisp/openai-key"
chmod 600 "$HOME/Library/Application Support/Wisp/openai-key"
```

You can change the compose model:

```bash
export WISP_OPENAI_MODEL="gpt-4.1-mini"
```

## Configuration

Optional environment variables:

```bash
export WISP_PYTHON="$HOME/.wisp/venv/bin/python3"
export WISP_MODEL="base.en"
export WISP_HINTS="names, companies, domain words"
export OPENAI_API_KEY="sk-..."
export WISP_OPENAI_MODEL="gpt-4.1-mini"
```

`base.en` is the default because it is fast and good enough for quick iteration. You can use larger Whisper models, for example:

```bash
export WISP_MODEL="large-v3-turbo"
```

The first run of a model may download weights.

## How It Works

1. Wisp records microphone audio and converts it to 16 kHz mono PCM.
2. The bundled Python worker receives PCM bytes through stdin.
3. `faster-whisper` runs one final transcription pass after recording stops.
4. Dictate mode lightly removes filler words and normalizes punctuation.
5. Compose mode sends the transcript to OpenAI for a concise rewrite.
6. The final result is copied to the clipboard and inserted once into the previous app when Accessibility permission allows it.

## Privacy

- Dictate mode runs transcription locally.
- Compose mode sends the transcript text to OpenAI.
- Wisp does not store transcripts by default.
- API keys are not committed or bundled. Store them in your shell environment or in the local Application Support file described above.

## Development

Run the full local check:

```bash
./scripts/test.sh
```

Build:

```bash
swift build -c release
```

Package:

```bash
./scripts/build_app.sh
```

Run logs:

```bash
tail -f /tmp/wisp.log
```

Smoke-test the Python worker:

```bash
say -o /tmp/wisp-test.aiff "hello this is a quick local dictation test"
ffmpeg -hide_banner -loglevel error -i /tmp/wisp-test.aiff -ac 1 -ar 16000 -f s16le - \
  | "$HOME/.wisp/venv/bin/python3" Sources/Wisp/Resources/stream_transcribe.py --model base.en
```

## Troubleshooting

**No microphone prompt appears**

Build and run the `.app` bundle instead of `swift run`. macOS requires the bundled `Info.plist` microphone usage description.

**The result copies but does not paste**

Grant Accessibility permission to Wisp in System Settings > Privacy & Security > Accessibility.

**Compose does not rewrite**

Check that `OPENAI_API_KEY` is set or that `~/Library/Application Support/Wisp/openai-key` exists and has `600` permissions.

**The first transcription is slow**

The selected Whisper model may be downloading or warming up. Try `WISP_MODEL=base.en` while testing.

## License

MIT
