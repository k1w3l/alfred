#!/usr/bin/env python3
"""Tiny helpers shared by Alfred fish scripts (profile flag / HERMES_HOME)."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
STATE_PATH = HOME / ".config" / "Hermes" / "alfred.json"
HERMES_AGENT = HOME / ".hermes" / "hermes-agent"


def boot() -> None:
    os.environ.setdefault("HERMES_HOME", str(HOME / ".hermes"))
    root = str(HERMES_AGENT)
    if root not in sys.path:
        sys.path.insert(0, root)


def current_profile() -> str:
    try:
        data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        name = str(data.get("profileName") or "").strip()
        if name:
            return name
    except Exception:
        pass
    boot()
    try:
        from hermes_cli.profiles import get_active_profile

        return get_active_profile() or "default"
    except Exception:
        return "default"


def profile_home(name: str | None = None) -> Path:
    boot()
    from hermes_cli.profiles import get_profile_dir

    return Path(get_profile_dir(name or current_profile()))


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "name"
    name = current_profile()
    if mode == "name":
        print(name)
        return 0
    if mode == "home":
        print(profile_home(name))
        return 0
    if mode == "flags":
        # Print hermes CLI args for fish to eval: empty or "-p name"
        if name and name != "default":
            print(f"-p\n{name}")
        return 0
    print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
