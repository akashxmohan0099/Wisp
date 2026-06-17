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

cat <<EOF

Whisper runtime installed.

Python: ${VENV_DIR}/bin/python3

You can now run:
  cd "${ROOT_DIR}"
  swift run Wisp

Optional:
  export WISP_PYTHON="${VENV_DIR}/bin/python3"
  export WISP_MODEL="base.en"
EOF
