#!/usr/bin/env python3
"""Transcribe a WAV with Voxtype and print JSON for the Alfred composer.

`voxtype transcribe` (v1.0.1) prints progress lines, then the transcript, and
does not type into the focused window. The model is whatever
~/.config/voxtype/config.toml already selects (large-v3-turbo here). Hermes
config is not touched.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

VOXTYPE_CONFIG = Path.home() / ".config" / "voxtype" / "config.toml"
MODEL_FILE = Path.home() / ".local" / "share" / "voxtype" / "models" / "ggml-large-v3-turbo.bin"

PROGRESS_PREFIXES = (
    "Loading audio file:",
    "Audio format:",
    "Resampling from ",
    "Processing ",
    "VAD:",
    "No speech detected",
)


def whisper_model(text: str) -> str:
    section = ""
    model = ""
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped
            continue
        if section == "[whisper]" and stripped.startswith("model") and "=" in stripped:
            model = stripped.split("=", 1)[1].strip().strip('"').strip("'")
    return model or "large-v3-turbo"


_LOG_LINE = re.compile(r"^\d{4}-\d{2}-\d{2}T\S+\s+(INFO|DEBUG|TRACE|WARN|ERROR)\b")


def clean_transcript(raw: str) -> str:
    kept: list[str] = []
    for line in raw.splitlines():
        stripped = line.strip()
        if any(stripped.startswith(prefix) for prefix in PROGRESS_PREFIXES):
            continue
        if _LOG_LINE.match(stripped):
            continue
        kept.append(line)
    return "\n".join(kept).strip()


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def fail(message: str, model: str = "") -> int:
    emit({
        "success": False,
        "transcript": "",
        "error": message,
        "provider": "voxtype",
        "model": model,
    })
    return 1


def configured_model() -> str:
    if not VOXTYPE_CONFIG.is_file():
        return "large-v3-turbo"
    return whisper_model(VOXTYPE_CONFIG.read_text(encoding="utf-8"))


def check() -> int:
    binary = shutil.which("voxtype") or ""
    model = configured_model()
    version = ""
    if binary:
        proc = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=15)
        blob = (proc.stdout or proc.stderr or "").strip()
        version = blob.splitlines()[0] if blob else ""
    print(json.dumps({
        "binary": binary,
        "version": version,
        "model": model,
        "modelFile": str(MODEL_FILE),
        "modelFileExists": MODEL_FILE.is_file(),
        "modelBytes": MODEL_FILE.stat().st_size if MODEL_FILE.is_file() else 0,
        "config": str(VOXTYPE_CONFIG),
    }))
    if not binary or not MODEL_FILE.is_file():
        return 1
    return 0


def transcribe(wav: str) -> int:
    path = Path(wav)
    if not path.is_file():
        return fail("missing wav")
    binary = shutil.which("voxtype")
    if not binary:
        return fail("voxtype not found")
    model = configured_model()
    try:
        proc = subprocess.run(
            [binary, "--quiet", "transcribe", str(path)],
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        return fail("voxtype transcribe timed out", model)
    text = clean_transcript(proc.stdout or "")
    if proc.returncode != 0 and text == "":
        err = (proc.stderr or proc.stdout or "").strip() or f"voxtype exited {proc.returncode}"
        return fail(err.splitlines()[-1][:400], model)
    emit({"success": True, "transcript": text, "provider": "voxtype", "model": model})
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        return check()
    if len(sys.argv) != 2:
        return fail("usage: transcribe.py <wav>")
    return transcribe(sys.argv[1])


if __name__ == "__main__":
    sys.exit(main())
