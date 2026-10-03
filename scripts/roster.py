#!/usr/bin/env python3
"""Profiles from the local Hermes install and every remote Desktop gateway.

A row is one profile on one gateway (`local:default`, `jarvis:tiberius`).
Selecting a row remembers both the gateway and the profile. Local rows also
run `hermes profile use`. Remote rows do not touch the local sticky profile.

  roster.py list
  roster.py set <key|profile-name>
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

sys.dont_write_bytecode = True

HOME = Path(os.path.expanduser("~"))
STATE_PATH = HOME / ".config" / "Hermes" / "alfred.json"
AUTH_PATH = HOME / ".config" / "Hermes" / "alfred-auth.json"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
CACHE_PATH = RUNTIME / "alfred-roster-cache.json"
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import gateways  # noqa: E402
import profiles as local_profiles  # noqa: E402

CACHE_TTL = 60.0

# One bloub identity per agent: shape, ink, expression, and which idle film.
# Names are the bloub catalogue (cercle, squircle, galet, …).
CURATED = {
    "alfred": {"shape": "cercle", "fill": "#0a0a0c", "expression": "neutre", "idle": 0},
    "jarvis": {"shape": "squircle", "fill": "#3b93f0", "expression": "attentif", "idle": 1},
    "tiberius": {"shape": "galet", "fill": "#8b5e3c", "expression": "colere", "idle": 2},
}

SHAPES = ["cercle", "galet", "squircle", "capsule", "triangle", "hexagone", "nuage", "goutte"]
EXPRESSIONS = [
    "neutre", "attentif", "surpris", "excite", "heureux", "hilare", "colere", "triste",
    "effraye", "mefiant", "confus", "curieux", "fier", "timide", "blase", "somnolent",
]
COLORS = [
    "#e8483f", "#f08a24", "#f0b429", "#3ecf8e", "#2fbfa0", "#8b5cf6", "#e152b0", "#a3a3a3",
]
SHAPE_ALIAS = {
    "circle": "cercle", "cercle": "cercle", "squircle": "squircle",
    "diamond": "hexagone", "hexagon": "hexagone", "hexagone": "hexagone",
    "drop": "goutte", "droplet": "goutte", "goutte": "goutte",
    "cloud": "nuage", "nuage": "nuage", "triangle": "triangle",
    "pebble": "galet", "galet": "galet", "capsule": "capsule",
}
EYES_ALIAS = {"soft": "neutre", "angry": "colere", "pause": "blase"}


def load_state() -> dict:
    return local_profiles.load_state()


def save_state(data: dict) -> None:
    local_profiles.save_state(data)


def load_auth(connection_id: str) -> dict:
    data = local_profiles.load_json(AUTH_PATH, {})
    entry = data.get(connection_id) if isinstance(data, dict) else None
    return entry if isinstance(entry, dict) else {}


def pretty_name(profile_id: str, display: str) -> str:
    shown = str(display or "").strip()
    if shown:
        return shown
    name = str(profile_id or "").strip() or "default"
    if name == "default":
        return "default"
    return name[:1].upper() + name[1:]


def digest_of(key: str) -> int:
    digest = 0
    for ch in key:
        digest = (digest * 33 + ord(ch)) & 0xFFFFFFFF
    return digest


def phase_of(key: str) -> float:
    return round((digest_of(key) % 10000) / 10000 * 9.0, 3)


def eyes_of(expression: str) -> str:
    if expression in ("colere", "mefiant"):
        return "angry"
    if expression in ("blase", "somnolent", "triste"):
        return "pause"
    return "soft"


def face_from(shape: str, fill: str, expression: str, idle: int, key: str) -> dict:
    expr = expression if expression in EXPRESSIONS else "neutre"
    return {
        "shape": SHAPE_ALIAS.get(shape, shape if shape in SHAPES else "cercle"),
        "fill": fill,
        "expression": expr,
        "idle": idle % 3,
        "phase": phase_of(key),
        "eyes": eyes_of(expr),
    }


def emoji_for(gateway_id: str, profile_id: str, label: str, overrides: dict) -> dict:
    key = f"{gateway_id}:{profile_id}"
    custom = overrides.get(key) if isinstance(overrides, dict) else None
    if isinstance(custom, dict) and custom.get("shape") and custom.get("fill"):
        expression = str(custom.get("expression") or EYES_ALIAS.get(str(custom.get("eyes") or ""), "neutre"))
        idle = int(custom.get("idle")) if str(custom.get("idle") or "").lstrip("-").isdigit() else digest_of(key) % 3
        return face_from(str(custom.get("shape")), str(custom.get("fill")), expression, idle, key)
    label_l = label.lower()
    pid = profile_id.lower()
    # Match the profile, not the gateway id — the Jarvis host also serves Tiberius.
    curated = None
    if "tiberius" in pid or "tiberius" in label_l:
        curated = CURATED["tiberius"]
    elif "jarvis" in pid or "jarvis" in label_l:
        curated = CURATED["jarvis"]
    elif "alfred" in pid or "alfred" in label_l or (gateway_id == "local" and pid == "default"):
        curated = CURATED["alfred"]
    if curated:
        return face_from(curated["shape"], curated["fill"], curated["expression"], curated["idle"], key)
    digest = digest_of(key)
    return face_from(
        SHAPES[digest % len(SHAPES)],
        COLORS[digest % len(COLORS)],
        EXPRESSIONS[digest % len(EXPRESSIONS)],
        digest % 3,
        key,
    )


def load_cache() -> dict:
    data = local_profiles.load_json(CACHE_PATH, {})
    return data if isinstance(data, dict) else {}


def save_cache(data: dict) -> None:
    try:
        CACHE_PATH.write_text(json.dumps(data), encoding="utf-8")
    except Exception:
        pass


def fetch_remote_profiles(connection: dict) -> tuple[list[dict], str]:
    cid = str(connection.get("id") or "")
    url = str(connection.get("url") or "").rstrip("/")
    if not url:
        return [], "missing url"
    cache = load_cache()
    slot = cache.get(cid) if isinstance(cache.get(cid), dict) else {}
    fresh = time.time() - float(slot.get("at") or 0) < CACHE_TTL
    if fresh and isinstance(slot.get("profiles"), list):
        return slot["profiles"], ""

    auth = load_auth(cid)
    username = str(auth.get("username") or auth.get("user") or "").strip()
    password = str(auth.get("password") or "").strip()
    token = str(auth.get("token") or "").strip()
    if not token and (not username or not password):
        if isinstance(slot.get("profiles"), list):
            return slot["profiles"], "auth missing; using cache"
        return [], "auth missing"

    try:
        import httpx
    except Exception:
        if isinstance(slot.get("profiles"), list):
            return slot["profiles"], "httpx missing; using cache"
        return [], "httpx missing"

    try:
        with httpx.Client(timeout=8.0, follow_redirects=True) as client:
            if token:
                response = client.get(url + "/api/profiles", headers={"Authorization": f"Bearer {token}"})
            else:
                login = client.post(
                    url + "/auth/password-login",
                    json={"provider": "basic", "username": username, "password": password},
                )
                if login.status_code >= 400:
                    raise RuntimeError(f"login {login.status_code}")
                response = client.get(url + "/api/profiles")
            if response.status_code >= 400:
                raise RuntimeError(f"profiles {response.status_code}")
            payload = response.json() if response.content else {}
    except Exception as exc:
        if isinstance(slot.get("profiles"), list):
            return slot["profiles"], str(exc)[:160]
        return [], str(exc)[:160]

    raw_rows = payload.get("profiles") if isinstance(payload, dict) else None
    if not isinstance(raw_rows, list):
        raw_rows = []
    rows = []
    for raw in raw_rows:
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("name") or "").strip()
        if not name:
            continue
        rows.append(
            {
                "id": name,
                "displayName": str(raw.get("display_name") or ""),
                "model": str(raw.get("model") or ""),
                "provider": str(raw.get("provider") or ""),
                "description": str(raw.get("description") or ""),
                "isDefault": bool(raw.get("is_default")),
                "gatewayRunning": bool(raw.get("gateway_running")),
            }
        )
    cache[cid] = {"at": time.time(), "profiles": rows}
    save_cache(cache)
    return rows, ""


def local_rows() -> list[dict]:
    try:
        rows, _current = local_profiles.list_rows()
    except Exception:
        rows = []
    if not rows:
        rows = [{"id": "default", "label": "Alfred", "displayName": "Alfred", "model": "", "provider": "", "description": "", "isDefault": True, "gatewayRunning": False}]
    return rows


def build_roster(state: dict) -> tuple[list[dict], list[str]]:
    overrides = state.get("profileEmoji") if isinstance(state.get("profileEmoji"), dict) else {}
    warnings: list[str] = []
    roster: list[dict] = []
    connections, _primary, _path = gateways.load_registry()
    for connection in connections:
        kind = str(connection.get("kind") or "local")
        gid = str(connection.get("id") or "local")
        glabel = str(connection.get("label") or gid)
        if kind == "local":
            source = local_rows()
        else:
            source, err = fetch_remote_profiles(connection)
            if err:
                warnings.append(f"{glabel}: {err}")
            if not source:
                continue
        for info in source:
            pid = str(info.get("id") or "").strip()
            if not pid:
                continue
            label = pretty_name(pid, str(info.get("displayName") or info.get("label") or ""))
            if kind == "local" and pid == "default" and label.lower() == "default":
                label = "Alfred"
            face = emoji_for(gid, pid, label, overrides)
            roster.append(
                {
                    "key": f"{gid}:{pid}",
                    "id": f"{gid}:{pid}",
                    "profileId": pid,
                    "gatewayId": gid,
                    "gatewayLabel": glabel,
                    "gatewayKind": kind,
                    "label": label,
                    "model": str(info.get("model") or ""),
                    "provider": str(info.get("provider") or ""),
                    "description": str(info.get("description") or ""),
                    "isDefault": bool(info.get("isDefault")),
                    "gatewayRunning": bool(info.get("gatewayRunning")),
                    "shape": face["shape"],
                    "fill": face["fill"],
                    "expression": face["expression"],
                    "idle": face["idle"],
                    "phase": face["phase"],
                    "eyes": face["eyes"],
                    "selected": False,
                }
            )
    return roster, warnings


def current_key(state: dict, rows: list[dict]) -> str:
    keys = {row["key"] for row in rows}
    stored = str(state.get("profileKey") or "").strip()
    if stored in keys:
        return stored
    guess = f"{str(state.get('connectionId') or 'local')}:{str(state.get('profileName') or 'default')}"
    if guess in keys:
        return guess
    for row in rows:
        if row["gatewayKind"] == "local" and row["profileId"] == "default":
            return row["key"]
    return rows[0]["key"] if rows else "local:default"


def resolve_key(rows: list[dict], want: str) -> str:
    needle = str(want or "").strip()
    if not needle:
        return ""
    for row in rows:
        if row["key"] == needle or row["id"] == needle:
            return row["key"]
    matches = [row for row in rows if row["profileId"] == needle or row["label"].lower() == needle.lower()]
    if len(matches) == 1:
        return matches[0]["key"]
    return ""


def default_binds(rows: list[dict]) -> list[dict]:
    binds = []
    for index, row in enumerate(rows[:9], start=1):
        binds.append(
            {
                "key": row["key"],
                "label": row["label"],
                "global": f"SUPER + ALT + {index}",
                "local": f"Ctrl+{index}",
            }
        )
    return binds


def sync_binds(state: dict, rows: list[dict]) -> bool:
    binds = default_binds(rows)
    if state.get("profileBinds") == binds:
        return False
    state["profileBinds"] = binds
    save_state(state)
    script = SCRIPT_DIR / "shortcuts.py"
    subprocess.run([sys.executable, "-B", str(script), "apply"], check=False, timeout=20, capture_output=True, text=True)
    return True


def decorate(rows: list[dict], state: dict, selected: str) -> None:
    binds = {str(item.get("key")): item for item in (state.get("profileBinds") or []) if isinstance(item, dict)}
    user = state.get("shortcuts") if isinstance(state.get("shortcuts"), dict) else {}
    global_over = user.get("global") if isinstance(user.get("global"), dict) else {}
    local_over = user.get("local") if isinstance(user.get("local"), dict) else {}
    for row in rows:
        row["selected"] = row["key"] == selected
        bind = binds.get(row["key"]) or {}
        ident = "profile:" + row["key"]
        row["shortcut"] = str(local_over.get(ident) or bind.get("local") or "")
        row["globalShortcut"] = str(global_over.get(ident) or bind.get("global") or "")


def payload(rows: list[dict], selected: str, warnings: list[str], binds_changed: bool) -> dict:
    current = next((row for row in rows if row["key"] == selected), rows[0] if rows else None)
    if current is None:
        return {"ok": False, "error": "no profiles", "current": "", "profiles": [], "warnings": warnings}
    return {
        "ok": True,
        "current": selected,
        "profileName": current["profileId"],
        "label": current["label"],
        "gatewayId": current["gatewayId"],
        "gatewayLabel": current["gatewayLabel"],
        "gatewayKind": current["gatewayKind"],
        "model": current.get("model") or "",
        "shape": current["shape"],
        "fill": current["fill"],
        "expression": current.get("expression") or "neutre",
        "idle": current.get("idle") or 0,
        "phase": current.get("phase") or 0,
        "eyes": current["eyes"],
        "profiles": rows,
        "warnings": warnings,
        "bindsChanged": binds_changed,
    }


def remember_gateway(connection_id: str) -> None:
    _rows, _primary, registry_path = gateways.load_registry()
    if registry_path and registry_path.is_file():
        data = gateways.load_json(registry_path, {})
        if isinstance(data, dict):
            data["lastUsed"] = connection_id
            gateways.save_json(registry_path, data)


def apply_selection(key: str) -> tuple[list[dict], str, list[str], bool]:
    state = load_state()
    rows, warnings = build_roster(state)
    resolved = resolve_key(rows, key)
    if not resolved:
        raise ValueError(f"unknown profile: {key}")
    chosen = next(row for row in rows if row["key"] == resolved)
    if chosen["gatewayKind"] == "local":
        local_profiles.set_profile(chosen["profileId"])
        state = load_state()
    state["connectionId"] = chosen["gatewayId"]
    state["profileName"] = chosen["profileId"]
    state["profileKey"] = chosen["key"]
    save_state(state)
    remember_gateway(chosen["gatewayId"])
    changed = sync_binds(state, rows)
    state = load_state()
    decorate(rows, state, chosen["key"])
    return rows, chosen["key"], warnings, changed


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    try:
        if mode == "set":
            rows, selected, warnings, changed = apply_selection(arg)
        else:
            state = load_state()
            rows, warnings = build_roster(state)
            selected = current_key(state, rows)
            changed = sync_binds(state, rows)
            state = load_state()
            decorate(rows, state, selected)
        print(json.dumps(payload(rows, selected, warnings, changed), ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "current": "", "profiles": [], "warnings": []}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
