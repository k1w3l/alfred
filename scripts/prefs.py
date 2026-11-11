#!/usr/bin/env python3
"""Alfred UI prefs: glassy vs classic theme.

  prefs.py get
  prefs.py set-theme classic|glassy
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True

HOME = Path(os.path.expanduser("~"))
STATE_PATH = HOME / ".config" / "Hermes" / "alfred.json"
SCRIPT_DIR = Path(__file__).resolve().parent

THEMES = (
    ("classic", "Classic"),
    ("glassy", "Glassy"),
)


def load_state() -> dict:
    try:
        data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_state(data: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(STATE_PATH)


def normalize_theme(value: str) -> str:
    key = str(value or "").strip().lower()
    if key in ("glass", "glassy", "frosted"):
        return "glassy"
    return "classic"


def theme_label(value: str) -> str:
    key = normalize_theme(value)
    for ident, label in THEMES:
        if ident == key:
            return label
    return "Classic"


def current_theme(state: dict | None = None) -> str:
    data = state if state is not None else load_state()
    return normalize_theme(str(data.get("uiTheme") or "classic"))


def dump(state: dict | None = None, error: str = "") -> dict:
    data = state if state is not None else load_state()
    theme = current_theme(data)
    return {
        "ok": error == "",
        "error": error,
        "theme": theme,
        "themeLabel": theme_label(theme),
        "themes": [{"id": ident, "label": label, "checked": ident == theme} for ident, label in THEMES],
    }


def sync_hypr(state: dict) -> str:
    if str(SCRIPT_DIR) not in sys.path:
        sys.path.insert(0, str(SCRIPT_DIR))
    import shortcuts

    shortcuts.write_hypr(state)
    return shortcuts.reload_hyprland()


def set_theme(value: str) -> dict:
    theme = normalize_theme(value)
    state = load_state()
    state["uiTheme"] = theme
    save_state(state)
    error = sync_hypr(state)
    return dump(state, error)


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "get"
    if mode in ("set-theme", "theme") and len(sys.argv) >= 2:
        value = sys.argv[2] if len(sys.argv) > 2 else ""
        payload = set_theme(value)
        print(json.dumps(payload, ensure_ascii=False))
        return 0 if payload.get("ok") else 1
    payload = dump()
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
