#!/usr/bin/env python3
"""List / select Hermes Desktop registered gateways for Alfred."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
STATE_PATH = HOME / ".config" / "Hermes" / "alfred.json"
CONNECTIONS_CANDIDATES = [
    HOME / ".config" / "Hermes" / "connections.json",
    HOME / ".config" / "hermes-desktop" / "connections.json",
    HOME / ".config" / "Hermes Desktop" / "connections.json",
]


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def find_connections_path() -> Path | None:
    for path in CONNECTIONS_CANDIDATES:
        if path.is_file():
            return path
    return None


def normalize_connection(raw: dict) -> dict | None:
    if not isinstance(raw, dict):
        return None
    cid = str(raw.get("id") or "").strip()
    if not cid:
        return None
    kind = str(raw.get("kind") or "local").strip().lower() or "local"
    label = str(raw.get("label") or raw.get("name") or cid).strip() or cid
    url = str(raw.get("url") or "").strip().rstrip("/")
    auth = str(raw.get("authMode") or raw.get("auth_mode") or "").strip().lower()
    return {
        "id": cid,
        "kind": kind,
        "label": label,
        "url": url,
        "authMode": auth,
        "host": str(raw.get("host") or ""),
        "user": str(raw.get("user") or ""),
        "port": raw.get("port") or 0,
    }


def load_registry() -> tuple[list[dict], str, Path | None]:
    path = find_connections_path()
    if path is None:
        local = {"id": "local", "kind": "local", "label": "This device", "url": "", "authMode": ""}
        return [local], "local", None
    data = load_json(path, {})
    rows = []
    for raw in data.get("connections") or []:
        row = normalize_connection(raw)
        if row:
            rows.append(row)
    if not any(r["id"] == "local" for r in rows):
        rows.insert(0, {"id": "local", "kind": "local", "label": "This device", "url": "", "authMode": ""})
    if not rows:
        rows = [{"id": "local", "kind": "local", "label": "This device", "url": "", "authMode": ""}]
    primary = str(data.get("primary") or data.get("lastUsed") or rows[0]["id"])
    return rows, primary, path


def load_state() -> dict:
    return load_json(STATE_PATH, {})


def save_state(data: dict) -> None:
    save_json(STATE_PATH, data)


def probe_remote(url: str) -> dict:
    if not url:
        return {"reachable": False, "gateway_running": False, "auth_required": False, "error": "missing url"}
    try:
        req = urllib.request.Request(url.rstrip("/") + "/api/status", method="GET")
        with urllib.request.urlopen(req, timeout=4) as resp:
            payload = json.loads(resp.read().decode("utf-8", "replace") or "{}")
        return {
            "reachable": True,
            "gateway_running": bool(payload.get("gateway_running")),
            "auth_required": bool(payload.get("auth_required")),
            "version": str(payload.get("version") or ""),
            "error": "",
        }
    except Exception as exc:
        return {
            "reachable": False,
            "gateway_running": False,
            "auth_required": False,
            "error": str(exc)[:200],
        }


def probe_local() -> dict:
    import subprocess

    try:
        out = subprocess.run(
            ["systemctl", "--user", "is-active", "hermes-gateway.service"],
            capture_output=True,
            text=True,
            timeout=4,
        )
        active = (out.stdout or "").strip() == "active"
        return {"reachable": True, "gateway_running": active, "auth_required": False, "error": ""}
    except Exception as exc:
        return {"reachable": False, "gateway_running": False, "auth_required": False, "error": str(exc)[:200]}


def decorate(rows: list[dict], current: str) -> list[dict]:
    out = []
    for row in rows:
        item = dict(row)
        item["selected"] = item["id"] == current
        if item["kind"] == "local":
            item.update(probe_local())
        elif item.get("url"):
            item.update(probe_remote(item["url"]))
        else:
            item.update({"reachable": False, "gateway_running": False, "auth_required": False, "error": "no url"})
        out.append(item)
    return out


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    rows, primary, registry_path = load_registry()
    state = load_state()
    current = str(state.get("connectionId") or primary or "local")
    ids = {r["id"] for r in rows}
    if current not in ids:
        current = primary if primary in ids else rows[0]["id"]

    if mode == "set":
        want = str(arg or "").strip()
        if want not in ids:
            print(json.dumps({"ok": False, "error": f"unknown gateway: {want}", "current": current, "connections": rows}))
            return 2
        state["connectionId"] = want
        # A profile name is only meaningful on its own gateway; never leave e.g. local + "tiberius".
        if not str(state.get("profileKey") or "").startswith(want + ":"):
            state["profileName"] = "default"
            state["profileKey"] = f"{want}:default"
        save_state(state)
        current = want
        if registry_path and registry_path.is_file():
            data = load_json(registry_path, {})
            data["lastUsed"] = want
            save_json(registry_path, data)

    connections = decorate(rows, current)
    selected = next((c for c in connections if c["id"] == current), connections[0])
    print(
        json.dumps(
            {
                "ok": True,
                "current": current,
                "label": selected.get("label") or current,
                "kind": selected.get("kind") or "local",
                "url": selected.get("url") or "",
                "reachable": bool(selected.get("reachable")),
                "gateway_running": bool(selected.get("gateway_running")),
                "connections": connections,
                "registry": str(registry_path) if registry_path else "",
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
