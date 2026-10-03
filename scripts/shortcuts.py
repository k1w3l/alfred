#!/usr/bin/env python3
"""Alfred keyboard shortcuts.

Global shortcuts become Hyprland binds in ~/.config/hypr/alfred.lua, loaded from
bindings.lua with `pcall(require, "hypr.alfred")`. Pill shortcuts only live in
~/.config/Hermes/alfred.json and are matched inside the overlay.

  shortcuts.py get
  shortcuts.py set <global|local> <id> <keys|default|"">
  shortcuts.py apply
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
STATE_PATH = HOME / ".config" / "Hermes" / "alfred.json"
HYPR_DIR = HOME / ".config" / "hypr"
HYPR_FILE = HYPR_DIR / "alfred.lua"
HOOK = 'pcall(require, "hypr.alfred")'

GLOBAL_ACTIONS = [
    ("toggle", "Show / hide Alfred", "SUPER + H", "omarchy-shell kiwel.alfred toggle"),
    ("voice", "Voice capture", "SUPER + ALT + H", "omarchy-shell kiwel.alfred voice"),
    ("newChat", "New chat", "", "omarchy-shell kiwel.alfred newchat"),
]

LOCAL_ACTIONS = [
    ("voice", "Voice capture", "Ctrl+M"),
    ("newChat", "New chat", "Ctrl+N"),
    ("closeChat", "Close chat", "Ctrl+W"),
    ("nextChat", "Next chat", "Ctrl+Tab"),
    ("prevChat", "Previous chat", "Ctrl+Shift+Tab"),
    ("sessions", "Previous sessions", "Ctrl+H"),
    ("preview", "Live preview", "Ctrl+P"),
]


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


def configured(state: dict, scope: str) -> dict:
    block = state.get("shortcuts") or {}
    values = block.get(scope) if isinstance(block, dict) else None
    return values if isinstance(values, dict) else {}


def profile_bind_rows(state: dict) -> list[dict]:
    rows = state.get("profileBinds") or []
    return [row for row in rows if isinstance(row, dict) and str(row.get("key") or "").strip()]


def resolved(state: dict) -> dict:
    out = {"global": [], "local": []}
    user = configured(state, "global")
    for key, label, default, command in GLOBAL_ACTIONS:
        out["global"].append({"id": key, "label": label, "keys": str(user.get(key, default)), "default": default, "command": command})
    user = configured(state, "local")
    for key, label, default in LOCAL_ACTIONS:
        out["local"].append({"id": key, "label": label, "keys": str(user.get(key, default)), "default": default})
    user_global = configured(state, "global")
    user_local = configured(state, "local")
    for row in profile_bind_rows(state):
        key = str(row.get("key") or "").strip()
        ident = "profile:" + key
        label = "Switch to " + str(row.get("label") or key)
        global_default = str(row.get("global") or "")
        local_default = str(row.get("local") or "")
        command = "omarchy-shell kiwel.alfred profile " + key
        out["global"].append({"id": ident, "label": label, "keys": str(user_global.get(ident, global_default)), "default": global_default, "command": command})
        out["local"].append({"id": ident, "label": label, "keys": str(user_local.get(ident, local_default)), "default": local_default})
    return out


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_hypr(state: dict) -> None:
    lines = [
        "-- Managed by Alfred (kiwel.alfred): pill gear menu > Keyboard shortcuts.",
        f"-- Loaded from bindings.lua with {HOOK}. Edits here are overwritten.",
        "",
    ]
    for row in resolved(state)["global"]:
        keys = row["keys"].strip()
        if not keys:
            continue
        lines.append(f"hl.unbind({lua_string(keys)})")
        lines.append(f"o.bind({lua_string(keys)}, {lua_string('Alfred: ' + row['label'])}, {lua_string(row['command'])})")
    HYPR_DIR.mkdir(parents=True, exist_ok=True)
    HYPR_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")


def hooked() -> bool:
    try:
        return "hypr.alfred" in (HYPR_DIR / "bindings.lua").read_text(encoding="utf-8")
    except Exception:
        return False


def reload_hyprland() -> str:
    try:
        subprocess.run(["hyprctl", "reload"], capture_output=True, text=True, timeout=10)
        errors = subprocess.run(["hyprctl", "configerrors"], capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception as exc:
        return str(exc)
    return "" if errors in ("", "no errors") else errors


def report(state: dict, error: str = "") -> dict:
    data = resolved(state)
    return {"ok": error == "", "error": error, "hooked": hooked(), "hyprFile": str(HYPR_FILE), **data}


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "get"
    state = load_state()
    if mode == "get":
        print(json.dumps(report(state), ensure_ascii=False))
        return 0
    if mode == "apply":
        write_hypr(state)
        print(json.dumps(report(state, reload_hyprland()), ensure_ascii=False))
        return 0
    if mode == "set" and len(sys.argv) >= 4:
        scope, action = sys.argv[2], sys.argv[3]
        keys = sys.argv[4].strip() if len(sys.argv) > 4 else ""
        actions = {a[0]: a for a in (GLOBAL_ACTIONS if scope == "global" else LOCAL_ACTIONS)}
        profile_ids = {"profile:" + str(row.get("key")) for row in profile_bind_rows(state)}
        if scope not in ("global", "local") or (action not in actions and action not in profile_ids):
            print(json.dumps(report(state, f"unknown shortcut {scope}/{action}"), ensure_ascii=False))
            return 1
        block = state.setdefault("shortcuts", {})
        values = block.setdefault(scope, {})
        if keys == "default":
            values.pop(action, None)
        else:
            values[action] = keys
        save_state(state)
        error = ""
        if scope == "global":
            write_hypr(state)
            error = reload_hyprland()
        print(json.dumps(report(state, error), ensure_ascii=False))
        return 0 if not error else 1
    print(json.dumps(report(state, "usage: shortcuts.py get | set <scope> <id> <keys> | apply"), ensure_ascii=False))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
