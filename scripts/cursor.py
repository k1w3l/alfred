#!/usr/bin/env python3
"""Stream the Hyprland pointer position for Alfred's eyes.

Each change prints one line on stdout: "X Y", in global logical coordinates
(what `hyprctl cursorpos` reports). A resting pointer prints nothing. The
socket is polled about 30 times a second.

The script exits when stdin closes (the shell that started it is gone), or
when the Hyprland socket has been unreachable for more than 5 s. Between
those, it keeps retrying the connection.
"""

from __future__ import annotations

import os
import re
import select
import socket
import sys
import time

sys.dont_write_bytecode = True

POLL_SECONDS = 1.0 / 30.0
GIVE_UP_AFTER = 5.0
REPLY = re.compile(rb"\s*(-?\d+)\s*,\s*(-?\d+)")


def socket_path() -> str | None:
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not runtime or not signature:
        return None
    return os.path.join(runtime, "hypr", signature, ".socket.sock")


def query_cursor(path: str) -> tuple[int, int] | None:
    """Ask Hyprland for the pointer once. None when the socket cannot answer."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            sock.connect(path)
            sock.sendall(b"cursorpos")
            chunks: list[bytes] = []
            while True:
                try:
                    data = sock.recv(256)
                except socket.timeout:
                    break
                if not data:
                    break
                chunks.append(data)
    except OSError:
        return None
    match = REPLY.match(b"".join(chunks))
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def wait_or_eof(seconds: float) -> bool:
    """Sleep for `seconds`. False when stdin reached EOF, meaning stop."""
    try:
        fd = sys.stdin.fileno()
    except (AttributeError, ValueError, OSError):
        time.sleep(seconds)
        return True
    readable, _, _ = select.select([fd], [], [], seconds)
    if not readable:
        return True
    try:
        return bool(os.read(fd, 4096))
    except OSError:
        return False


def main() -> int:
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except AttributeError:
        pass

    last: tuple[int, int] | None = None
    last_ok = time.monotonic()

    while True:
        started = time.monotonic()
        path = socket_path()
        pos = query_cursor(path) if path else None

        if pos is not None:
            last_ok = started
            if pos != last:
                last = pos
                print(f"{pos[0]} {pos[1]}", flush=True)
        elif started - last_ok > GIVE_UP_AFTER:
            return 0

        remaining = max(0.0, POLL_SECONDS - (time.monotonic() - started))
        if not wait_or_eof(remaining):
            return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        raise SystemExit(0)
