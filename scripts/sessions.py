#!/usr/bin/env python3
"""List and load Hermes sessions from the active profile's state.db (read-only).

  sessions.py list [limit]   -> {"ok", "sessions": [{id, title, preview, source, lastActive, messageCount}]}
  sessions.py load <id>      -> {"ok", "id", "title", "messages": [{role, text}]}
"""

from __future__ import annotations

import importlib.util
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

# Any file written under the plugin dir (e.g. __pycache__) makes Omarchy hot-reload the plugin.
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
HIDDEN_SOURCES = ("cron",)
MESSAGE_CAP = 200


def profile_home() -> Path:
    try:
        spec = importlib.util.spec_from_file_location("alfred_profile", HERE / "alfred-profile.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return Path(mod.profile_home())
    except Exception:
        return Path(os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))


def connect() -> sqlite3.Connection:
    db = profile_home() / "state.db"
    if not db.exists():
        raise FileNotFoundError(f"no session store at {db}")
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=2.0)
    conn.row_factory = sqlite3.Row
    return conn


def columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}


def relative(ts: float | None) -> str:
    if not ts:
        return ""
    delta = max(0, int(time.time() - float(ts)))
    if delta < 60:
        return "now"
    if delta < 3600:
        return f"{delta // 60}m"
    if delta < 86400:
        return f"{delta // 3600}h"
    return f"{delta // 86400}d"


def first_user_text(conn: sqlite3.Connection, session_id: str) -> str:
    row = conn.execute(
        "SELECT content FROM messages WHERE session_id = ? AND role = 'user' "
        "AND content IS NOT NULL AND content != '' ORDER BY id LIMIT 1",
        (session_id,),
    ).fetchone()
    return " ".join(str(row[0]).split())[:120] if row else ""


def list_sessions(limit: int) -> dict:
    conn = connect()
    cols = columns(conn, "sessions")
    activity = "COALESCE(last_activity_at, ended_at, started_at)" if "last_activity_at" in cols else "COALESCE(ended_at, started_at)"
    filters = ["source NOT IN (%s)" % ",".join("?" for _ in HIDDEN_SOURCES), "COALESCE(message_count, 0) > 0"]
    for flag in ("archived", "hidden"):
        if flag in cols:
            filters.append(f"COALESCE({flag}, 0) = 0")
    rows = conn.execute(
        f"SELECT id, title, source, message_count, {activity} AS active_at FROM sessions "
        f"WHERE {' AND '.join(filters)} ORDER BY active_at DESC LIMIT ?",
        (*HIDDEN_SOURCES, limit),
    ).fetchall()
    out = []
    for row in rows:
        preview = first_user_text(conn, row["id"])
        title = str(row["title"] or "").strip() or preview or row["id"]
        out.append({
            "id": row["id"],
            "title": title,
            "preview": preview,
            "source": row["source"] or "",
            "lastActive": relative(row["active_at"]),
            "messageCount": int(row["message_count"] or 0),
        })
    return {"ok": True, "sessions": out}


def load_session(session_id: str) -> dict:
    conn = connect()
    head = conn.execute("SELECT id, title FROM sessions WHERE id = ?", (session_id,)).fetchone()
    if head is None:
        return {"ok": False, "error": f"session {session_id} not found"}
    cols = columns(conn, "messages")
    active = " AND COALESCE(active, 1) = 1" if "active" in cols else ""
    rows = conn.execute(
        "SELECT role, content FROM messages WHERE session_id = ? AND role IN ('user', 'assistant') "
        f"AND content IS NOT NULL AND TRIM(content) != ''{active} ORDER BY id DESC LIMIT ?",
        (session_id, MESSAGE_CAP),
    ).fetchall()
    messages = [{"role": r["role"], "text": str(r["content"])} for r in reversed(rows)]
    return {"ok": True, "id": head["id"], "title": str(head["title"] or ""), "messages": messages}


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    try:
        if mode == "list":
            limit = int(sys.argv[2]) if len(sys.argv) > 2 else 30
            result = list_sessions(max(1, min(limit, 200)))
        elif mode == "load" and len(sys.argv) > 2:
            result = load_session(sys.argv[2])
        else:
            result = {"ok": False, "error": "usage: sessions.py list [limit] | load <id>"}
    except Exception as exc:
        result = {"ok": False, "error": str(exc), "sessions": []}
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
