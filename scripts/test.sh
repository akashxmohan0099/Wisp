#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release
swift test
python3 -m py_compile Sources/Wisp/Resources/stream_transcribe.py

if [[ -x "$HOME/.wisp/venv/bin/python3" ]] && command -v ffmpeg >/dev/null && command -v say >/dev/null; then
  tmp_audio="$(mktemp /tmp/wisp-smoke-XXXXXX.aiff)"
  trap 'rm -f "$tmp_audio"' EXIT

  say -o "$tmp_audio" "hello this is a quick local dictation test"
  transcript="$(ffmpeg -hide_banner -loglevel error -i "$tmp_audio" -ac 1 -ar 16000 -f s16le - | "$HOME/.wisp/venv/bin/python3" Sources/Wisp/Resources/stream_transcribe.py --model base.en)"

  echo "$transcript" | grep -qi "quick local dictation test"
else
  echo "Skipping local Whisper smoke test; install runtime with ./scripts/setup_whisper.sh"
fi
