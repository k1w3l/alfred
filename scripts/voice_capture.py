#!/usr/bin/env python3
"""Record a WAV with pw-record and print live levels on stdout.

Each line is: LEVEL <0-1> <capturing 0|1> <hearing 0|1>
capturing means new samples landed in the file. hearing means the latest
chunk is above speech level, so a silent mic stays distinct from a live one.
"""

from __future__ import annotations

import math
import os
import shutil
import signal
import struct
import subprocess
import sys
import time
import wave

# Speech RMS (0-1 of full scale). Room tone sits well under this.
HEAR_RMS = 0.045
# Map RMS into a 0-1 meter. Normal speech lands near the top.
GAIN = 7.0


def recorder_command(target: str) -> list[str] | None:
    if shutil.which("pw-record"):
        return [
            "pw-record",
            "--rate",
            "16000",
            "--channels",
            "1",
            "--latency",
            "50ms",
            target,
        ]
    if shutil.which("parecord"):
        return ["parecord", "--rate=16000", "--channels=1", target]
    return None


def data_offset(path: str) -> int:
    try:
        with open(path, "rb") as handle:
            head = handle.read(256)
    except OSError:
        return 44
    at = head.find(b"data")
    if at < 0 or at + 8 > len(head):
        return 44
    return at + 8


def read_level(path: str, previous_size: int) -> tuple[float, int, bool, bool]:
    try:
        size = os.path.getsize(path)
    except OSError:
        return 0.0, 0, False, False
    offset = data_offset(path)
    capturing = size > previous_size and size > offset
    if size <= offset + 2:
        return 0.0, size, capturing, False
    # Last 100ms at 16 kHz mono s16.
    want = 3200
    try:
        with open(path, "rb") as handle:
            handle.seek(max(offset, size - want))
            raw = handle.read(want)
    except OSError:
        return 0.0, size, capturing, False
    count = len(raw) // 2
    if count <= 0:
        return 0.0, size, capturing, False
    samples = struct.unpack("<" + "h" * count, raw[: count * 2])
    total = 0.0
    for sample in samples:
        total += sample * sample
    rms = math.sqrt(total / count) / 32768.0
    level = min(1.0, rms * GAIN)
    return level, size, capturing, rms >= HEAR_RMS


def emit(level: float, capturing: bool, hearing: bool) -> None:
    print(
        f"LEVEL {level:.4f} {1 if capturing else 0} {1 if hearing else 0}",
        flush=True,
    )


def record(target: str) -> int:
    command = recorder_command(target)
    if command is None:
        print("pw-record not found", file=sys.stderr)
        return 127
    try:
        os.remove(target)
    except FileNotFoundError:
        pass
    # Own session so a SIGTERM aimed at this process does not tear down
    # pw-record before it can finish the WAV header.
    proc = subprocess.Popen(command, start_new_session=True)
    stop = False

    def request_stop(signum, frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    previous = 0
    while not stop:
        if proc.poll() is not None:
            break
        level, previous, capturing, hearing = read_level(target, previous)
        emit(level, capturing, hearing)
        time.sleep(0.1)

    if proc.poll() is None:
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=1.2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=0.5)
    return 0


def self_test() -> int:
    path = "/tmp/alfred-voice-level-selftest.wav"
    rate = 16000
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        frames = bytearray()
        for i in range(rate):
            # 440 Hz at about 0.2 full scale: clearly above HEAR_RMS.
            sample = int(0.2 * 32767 * math.sin(2 * math.pi * 440 * i / rate))
            frames += struct.pack("<h", sample)
        handle.writeframes(frames)
    level, size, capturing, hearing = read_level(path, 0)
    print(
        f"self-test level={level:.3f} bytes={size} capturing={int(capturing)} hearing={int(hearing)}"
    )
    if not capturing or not hearing or level < 0.5:
        return 1
    quiet, _, _, quiet_hear = read_level(path, size)
    # Same file, no growth: not a new capture, but the samples are still loud.
    if quiet_hear is False or quiet < 0.5:
        return 1
    return 0


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return self_test()
    if len(sys.argv) != 2 or not sys.argv[1]:
        print("usage: voice_capture.py <wav> | --self-test", file=sys.stderr)
        return 2
    return record(sys.argv[1])


if __name__ == "__main__":
    sys.exit(main())
