#!/usr/bin/env python3

"""Wisp transcription worker — click-to-toggle mode.

Started when the user clicks the bubble (or hits the shortcut). Reads raw
16kHz mono int16 PCM on stdin. When stdin closes (the user clicked stop), runs
one high-quality transcription pass and emits the final text before exiting.

Event contract (consumed by TranscriptionService.swift):
  {"type": "status",  "message": str}
  {"type": "append",  "text": str}
  {"type": "replace", "undo": int, "text": str}
  {"type": "error",   "message": str}
  {"type": "done",    "runtime": str, "model": str}
"""

import argparse
import json
import os
import signal
import sys
import threading
from typing import Optional

import numpy as np
from faster_whisper import WhisperModel

SAMPLE_RATE = 16_000
MIN_FINAL_AUDIO = 0.3          # below this, skip final pass
MAX_BUFFER_SECONDS = 600.0     # hard cap on audio we'll buffer

INITIAL_PROMPT = (
    "Transcribe spoken English dictation as polished written English with correct punctuation, "
    "capitalization, apostrophes, and common word corrections. Preserve names, places, companies, "
    "product names, and proper nouns exactly when spoken."
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="base.en", help="final/quality model")
    return parser.parse_args()


def emit(event: dict) -> None:
    sys.stdout.write(json.dumps(event, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def build_prompt(custom_hints: str) -> str:
    if custom_hints:
        return f"{INITIAL_PROMPT} Prefer these names and terms when they sound close: {custom_hints}."
    return INITIAL_PROMPT


def load_model(model_name: str, role: str) -> WhisperModel:
    emit({"type": "status", "message": f"Loading {role} model {model_name}..."})
    return WhisperModel(
        model_name,
        device="cpu",
        compute_type="int8",
        cpu_threads=max(4, os.cpu_count() or 4),
        num_workers=1,
    )


def transcribe(model: WhisperModel, audio: np.ndarray, beam: int, custom_hints: str) -> str:
    if audio.size == 0:
        return ""
    samples = audio.astype(np.float32) / 32768.0
    segments, _ = model.transcribe(
        samples,
        language="en",
        beam_size=beam,
        best_of=beam,
        temperature=0.0,
        compression_ratio_threshold=2.4,
        log_prob_threshold=-1.0,
        no_speech_threshold=0.5,
        condition_on_previous_text=False,
        vad_filter=False,
        word_timestamps=False,
        hotwords=custom_hints or None,
        initial_prompt=build_prompt(custom_hints),
    )
    parts = [s.text.strip() for s in segments]
    return " ".join(p for p in parts if p)


class StreamState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.closed = False
        self.audio_bytes = bytearray()
        self.total_samples_seen = 0

    def append(self, pcm_bytes: bytes) -> None:
        if not pcm_bytes:
            return
        with self.lock:
            self.audio_bytes.extend(pcm_bytes)
            self.total_samples_seen += len(pcm_bytes) // 2
            max_bytes = int(MAX_BUFFER_SECONDS * SAMPLE_RATE * 2)
            if len(self.audio_bytes) > max_bytes:
                del self.audio_bytes[: len(self.audio_bytes) - max_bytes]

    def snapshot(self) -> tuple[np.ndarray, int]:
        with self.lock:
            return np.frombuffer(bytes(self.audio_bytes), dtype=np.int16), self.total_samples_seen

    def close(self) -> None:
        with self.lock:
            self.closed = True

    def is_closed(self) -> bool:
        with self.lock:
            return self.closed


def read_stdin(state: StreamState) -> None:
    while True:
        chunk = sys.stdin.buffer.read(4096)
        if not chunk:
            state.close()
            return
        state.append(chunk)


def run(final_model_name: str) -> int:
    custom_hints = os.environ.get("WISP_HINTS", os.environ.get("VOICE_TO_TEXT_HINTS", "")).strip()

    final_model = load_model(final_model_name, "local Whisper")

    emit({"type": "status", "message": "Ready. Speak now."})

    state = StreamState()
    read_stdin(state)

    audio, _ = state.snapshot()
    if audio.size >= int(MIN_FINAL_AUDIO * SAMPLE_RATE):
        emit({"type": "status", "message": "Transcribing..."})
        final_text = transcribe(final_model, audio, beam=5, custom_hints=custom_hints)
        if final_text:
            emit({"type": "append", "text": final_text})

    emit({"type": "done", "runtime": "faster-whisper", "model": final_model_name})
    return 0


def main() -> int:
    args = parse_args()
    final_model = os.environ.get("WISP_MODEL", os.environ.get("VOICE_TO_TEXT_MODEL", args.model))

    def stop_handler(signum: int, frame: Optional[object]) -> None:
        raise KeyboardInterrupt()

    signal.signal(signal.SIGTERM, stop_handler)

    try:
        return run(final_model)
    except KeyboardInterrupt:
        return 0
    except Exception as exc:
        emit({"type": "error", "message": str(exc)})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
