#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${HOME}/.wisp"
VENV_DIR="${INSTALL_DIR}/venv"

mkdir -p "${INSTALL_DIR}"

PYTHON_BIN="/opt/homebrew/bin/python3"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

"${PYTHON_BIN}" -m venv --clear "${VENV_DIR}"
"${VENV_DIR}/bin/python3" -m pip install --upgrade pip setuptools wheel
"${VENV_DIR}/bin/python3" -m pip install faster-whisper numpy

MODEL_NAME="${WISP_MODEL_DOWNLOAD:-base.en}"

cat <<EOF

Downloading the default local Whisper model: ${MODEL_NAME}
This can take a few minutes the first time.
EOF

"${VENV_DIR}/bin/python3" - <<EOF
from faster_whisper import WhisperModel

WhisperModel("${MODEL_NAME}", device="cpu", compute_type="int8")
print("Downloaded ${MODEL_NAME}")
EOF

if ! command -v ffmpeg >/dev/null; then
  FFMPEG_NOTE='ffmpeg was not found. Install it with: brew install ffmpeg'
else
  FFMPEG_NOTE='ffmpeg is installed.'
fi

cat <<EOF

Whisper runtime installed.

Python: ${VENV_DIR}/bin/python3
Model: ${MODEL_NAME}
${FFMPEG_NOTE}

You can now run:
  cd "${ROOT_DIR}"
  ./scripts/build_app.sh
  open dist/Wisp.app

Optional:
  export WISP_PYTHON="${VENV_DIR}/bin/python3"
  export WISP_MODEL="${MODEL_NAME}"
EOF
