#!/usr/bin/env python3
"""List / select Hermes profiles for Alfred (hermes profile list / use)."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
STATE_PATH = HOME / ".config" / "Hermes" / "alfred.json"
HERMES_AGENT = HOME / ".hermes" / "hermes-agent"


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def boot_hermes() -> None:
    os.environ.setdefault("HERMES_HOME", str(HOME / ".hermes"))
    root = str(HERMES_AGENT)
    if root not in sys.path:
        sys.path.insert(0, root)


def load_state() -> dict:
    return load_json(STATE_PATH, {})


def save_state(data: dict) -> None:
    save_json(STATE_PATH, data)


def profile_label(info) -> str:
    display = str(getattr(info, "display_name", "") or "").strip()
    name = str(getattr(info, "name", "") or "").strip() or "default"
    if display and display.lower() != name.lower():
        if name == "default":
            return display
        return f"{display} ({name})"
    if name == "default":
        return display or "default"
    return name


def list_rows() -> tuple[list[dict], str]:
    boot_hermes()
    from hermes_cli.profiles import get_active_profile, list_profiles

    sticky = get_active_profile() or "default"
    state = load_state()
    current = str(state.get("profileName") or sticky or "default").strip() or "default"
    rows = []
    ids = set()
    for info in list_profiles(lazy_skill_count=True):
        name = str(info.name or "").strip()
        if not name or name in ids:
            continue
        ids.add(name)
        rows.append(
            {
                "id": name,
                "label": profile_label(info),
                "displayName": str(getattr(info, "display_name", "") or ""),
                "model": str(getattr(info, "model", "") or ""),
                "provider": str(getattr(info, "provider", "") or ""),
                "description": str(getattr(info, "description", "") or ""),
                "isDefault": bool(getattr(info, "is_default", False)),
                "gatewayRunning": bool(getattr(info, "gateway_running", False)),
                "selected": False,
            }
        )
    if not rows:
        rows = [
            {
                "id": "default",
                "label": "default",
                "displayName": "",
                "model": "",
                "provider": "",
                "description": "",
                "isDefault": True,
                "gatewayRunning": False,
                "selected": True,
            }
        ]
    if current not in {r["id"] for r in rows}:
        current = sticky if sticky in {r["id"] for r in rows} else rows[0]["id"]
    for row in rows:
        row["selected"] = row["id"] == current
    return rows, current


def set_profile(name: str) -> tuple[list[dict], str]:
    boot_hermes()
    from hermes_cli.profiles import set_active_profile

    want = str(name or "").strip() or "default"
    set_active_profile(want)
    state = load_state()
    state["profileName"] = want
    save_state(state)
    return list_rows()


def selected_label(rows: list[dict], current: str) -> str:
    for row in rows:
        if row["id"] == current:
            return str(row.get("label") or current)
    return current


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    try:
        if mode == "set":
            rows, current = set_profile(arg)
        else:
            rows, current = list_rows()
        selected = next((r for r in rows if r["id"] == current), rows[0])
        print(
            json.dumps(
                {
                    "ok": True,
                    "current": current,
                    "label": selected_label(rows, current),
                    "model": selected.get("model") or "",
                    "provider": selected.get("provider") or "",
                    "gatewayRunning": bool(selected.get("gatewayRunning")),
                    "profiles": rows,
                },
                ensure_ascii=False,
            )
        )
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "current": "default", "label": "default", "profiles": []}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
