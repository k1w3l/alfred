#!/usr/bin/env python3
"""Send a oneshot prompt to a remote Hermes Desktop gateway over WebSocket RPC."""

from __future__ import annotations

import asyncio
import json
import os
import sys
import urllib.parse
from contextlib import asynccontextmanager
from http.cookiejar import CookieJar
from pathlib import Path
from typing import Any

import httpx
import websockets

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import gateways  # noqa: E402


def auth_for(connection_id: str) -> dict:
    return gateways.load_auth(connection_id)


async def pick_source(ws) -> str:
    try:
        desc = await rpc(ws, "runtime.describe", timeout=10)
        sources = list(((desc or {}).get("session_create") or {}).get("sources") or [])
    except Exception:
        sources = []
    for candidate in ("oneshot", "cli", "tool", "desktop"):
        if candidate in sources:
            return candidate
    return sources[0] if sources else "cli"


def ws_base(http_url: str) -> str:
    parsed = urllib.parse.urlparse(http_url)
    scheme = "wss" if parsed.scheme == "https" else "ws"
    prefix = parsed.path.rstrip("/")
    return f"{scheme}://{parsed.netloc}{prefix}"


async def mint_ticket(client: httpx.AsyncClient, base: str) -> str:
    resp = await client.post(f"{base}/api/auth/ws-ticket")
    if resp.status_code >= 400:
        raise RuntimeError(f"ws-ticket failed ({resp.status_code}): {resp.text[:200]}")
    payload = resp.json() if resp.content else {}
    ticket = str(payload.get("ticket") or payload.get("token") or "").strip()
    if not ticket:
        raise RuntimeError("ws-ticket response missing ticket")
    return ticket


async def login_password(client: httpx.AsyncClient, base: str, username: str, password: str) -> None:
    resp = await client.post(
        f"{base}/auth/password-login",
        json={"provider": "basic", "username": username, "password": password},
    )
    if resp.status_code >= 400:
        raise RuntimeError(f"password login failed ({resp.status_code}): {resp.text[:200]}")


LEVELS = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
ALFRED_JSON = Path.home() / ".config" / "Hermes" / "alfred.json"


def profile_params(profile: str) -> dict:
    name = str(profile or "").strip()
    if name and name != "default":
        return {"profile": name}
    return {}


def remember_effort(connection_id: str, level: str) -> None:
    """Remember the effort for this gateway only.

    ``reasoningEffort`` stays the local fallback. A remote list must not overwrite it,
    or the next local send would pin the remote level onto this machine.
    """
    data: dict = {}
    try:
        loaded = json.loads(ALFRED_JSON.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            data = loaded
    except Exception:
        data = {}
    by = data.get("reasoningByGateway")
    if not isinstance(by, dict):
        by = {}
    by[str(connection_id or "")] = level
    data["reasoningByGateway"] = by
    ALFRED_JSON.parent.mkdir(parents=True, exist_ok=True)
    ALFRED_JSON.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def effort_for(connection_id: str) -> str:
    try:
        data = json.loads(ALFRED_JSON.read_text(encoding="utf-8"))
    except Exception:
        return ""
    by = data.get("reasoningByGateway") if isinstance(data, dict) else None
    if not isinstance(by, dict):
        return ""
    return str(by.get(str(connection_id or "")) or "").strip()


@asynccontextmanager
async def gateway_ws(url: str, connection_id: str):
    auth = auth_for(connection_id)
    token = str(auth.get("token") or os.environ.get("ALFRED_GATEWAY_TOKEN") or "").strip()
    username = str(auth.get("username") or auth.get("user") or os.environ.get("ALFRED_GATEWAY_USER") or "").strip()
    password = str(auth.get("password") or os.environ.get("ALFRED_GATEWAY_PASSWORD") or "").strip()
    base = url.rstrip("/")
    cookies = CookieJar()
    async with httpx.AsyncClient(timeout=30.0, cookies=cookies, follow_redirects=True) as client:
        if token:
            ws_url = f"{ws_base(base)}/api/ws?token={urllib.parse.quote(token)}"
        else:
            if not username or not password:
                raise RuntimeError(
                    "Remote gateway needs auth. Add ~/.config/Hermes/alfred-auth.json "
                    f'like {{"{connection_id}": {{"username": "...", "password": "..."}}}} '
                    'or {"token": "..."} for token-mode gateways.'
                )
            await login_password(client, base, username, password)
            ticket = await mint_ticket(client, base)
            ws_url = f"{ws_base(base)}/api/ws?ticket={urllib.parse.quote(ticket)}"
        async with websockets.connect(ws_url, open_timeout=20, max_size=8 * 1024 * 1024) as ws:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=5)
                msg = json.loads(raw)
                if unwrap_event(msg)[0] == "gateway.ready":
                    await rpc(ws, "client.capabilities", {"server_requests": True}, timeout=10)
            except Exception:
                pass
            yield ws


async def read_reasoning(ws, profile: str) -> str:
    result = await rpc(ws, "config.get", {"key": "reasoning", **profile_params(profile)}, timeout=15)
    if not isinstance(result, dict):
        return ""
    return str(result.get("value") or "").strip().lower()


async def write_reasoning(ws, level: str, profile: str, session_id: str = "", scope: str = "") -> None:
    params: dict = {"key": "reasoning", "value": level, **profile_params(profile)}
    if session_id:
        params["session_id"] = session_id
    if scope:
        params["scope"] = scope
    await rpc(ws, "config.set", params, timeout=15)


async def apply_reasoning(ws, reasoning: str, profile: str, session_id: str) -> None:
    """Pin the live session, and persist the profile default when the session pin cannot land.

    A brand-new session also receives ``reasoning_effort`` on ``session.create``, before the
    agent is built. This call covers resume, where the agent already exists, and the case
    where the runtime id is not in the gateway's session table.
    """
    level = str(reasoning or "").strip().lower()
    if not level:
        return
    if session_id:
        try:
            await write_reasoning(ws, level, profile, session_id=session_id)
            return
        except Exception:
            pass
    await write_reasoning(ws, level, profile, scope="global")


async def rpc(ws, method: str, params: dict | None = None, timeout: float = 30.0) -> Any:
    req_id = f"alfred-{method}-{os.getpid()}-{id(params)}"
    await ws.send(json.dumps({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params or {}}))
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        remaining = deadline - asyncio.get_event_loop().time()
        if remaining <= 0:
            raise TimeoutError(f"RPC timeout waiting for {method}")
        raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
        msg = json.loads(raw)
        if msg.get("id") == req_id:
            if "error" in msg and msg["error"]:
                err = msg["error"]
                raise RuntimeError(f"{method}: {err.get('message') or err}")
            return msg.get("result")
        # server→client request: refuse unsupported methods quickly
        if msg.get("method") and msg.get("id") and "result" not in msg:
            await ws.send(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": msg["id"],
                        "error": {"code": -32601, "message": "Method not supported by Alfred HUD"},
                    }
                )
            )


def emit(event: dict) -> None:
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def unwrap_event(msg: dict) -> tuple[str, str, dict]:
    """(type, session_id, payload) for both `{"method":"event","params":{type,payload}}` and bare methods."""
    method = str(msg.get("method") or "")
    params = msg.get("params") or {}
    if not isinstance(params, dict):
        params = {}
    if method == "event":
        payload = params.get("payload")
        return str(params.get("type") or ""), str(params.get("session_id") or ""), payload if isinstance(payload, dict) else {}
    return method, str(params.get("session_id") or ""), params


async def collect_reply(ws, session_id: str, stored_id: str, timeout: float = 600.0) -> str:
    chunks: list[str] = []
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        remaining = deadline - asyncio.get_event_loop().time()
        if remaining <= 0:
            raise TimeoutError("Timed out waiting for remote reply")
        raw = await asyncio.wait_for(ws.recv(), timeout=remaining)
        msg = json.loads(raw)
        method = str(msg.get("method") or "")
        params = msg.get("params") or {}
        # Answer server requests so the turn does not stall forever.
        if method and method != "event" and msg.get("id") and "result" not in msg:
            if method == "approval":
                await ws.send(json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": {"choice": "once"}}))
            else:
                await ws.send(
                    json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": msg["id"],
                            "error": {"code": -32601, "message": "Unsupported by Alfred"},
                        }
                    )
                )
            continue
        kind, sid, payload = unwrap_event(msg)
        if sid not in ("", session_id):
            continue
        if kind == "message.delta":
            text = payload.get("text") or payload.get("delta") or ""
            if text:
                chunks.append(str(text))
                emit({"type": "text", "text": str(text)})
        elif kind in ("message.complete", "message.done"):
            final = payload.get("text") or payload.get("content") or "".join(chunks)
            if not isinstance(final, str):
                final = json.dumps(final, ensure_ascii=False)
            result = {"type": "result", "text": final, "session_id": stored_id}
            if str(payload.get("status") or "") == "error":
                result["error"] = final or "remote turn failed"
            emit(result)
            return final
        elif kind in ("error", "session.error") and sid:
            raise RuntimeError(str(payload.get("message") or payload or "remote error"))


async def run(url: str, connection_id: str, session_name: str, prompt: str, reasoning: str, profile: str = "") -> int:
    async with gateway_ws(url, connection_id) as ws:
        scope = profile_params(profile)
        created = None
        fresh = True
        # "id:<stored>" continues a session this gateway+profile issued; anything else is a fresh turn.
        if session_name.startswith("id:"):
            try:
                created = await rpc(
                    ws,
                    "session.resume",
                    {"session_id": session_name[3:], "omit_messages": True, **scope},
                    timeout=30,
                )
                fresh = False
            except Exception:
                created = None
                fresh = True
        if not isinstance(created, dict) or not (created.get("session_id") or created.get("id")):
            title = "" if session_name.startswith("id:") else session_name
            source = await pick_source(ws)
            body = {"source": source, **scope}
            if title:
                body["title"] = title
            # Must be present before the gateway schedules the agent build. A later
            # config.set loses the race and the turn keeps the profile default.
            if reasoning:
                body["reasoning_effort"] = reasoning
            created = await rpc(ws, "session.create", body, timeout=30)
            fresh = True
        session_id = ""
        stored_id = ""
        if isinstance(created, dict):
            session_id = str(created.get("session_id") or created.get("id") or "")
            stored_id = str(created.get("stored_session_id") or created.get("resumed") or session_id)
        if not session_id:
            raise RuntimeError(f"session.create returned no id: {created}")
        emit({"type": "system", "session_id": stored_id})

        # Resume already built the agent from the old pin. Create still gets a
        # session pin in case the build finished before this returns.
        if reasoning and not fresh:
            try:
                await apply_reasoning(ws, reasoning, profile, session_id)
            except Exception:
                pass
        elif reasoning and fresh:
            try:
                await write_reasoning(ws, reasoning, profile, session_id=session_id)
            except Exception:
                pass

        await rpc(ws, "prompt.submit", {"session_id": session_id, "text": prompt}, timeout=30)
        await collect_reply(ws, session_id, stored_id)
    return 0


def emit_effort(ok: bool, current: str, error: str = "") -> None:
    payload = {"ok": ok, "current": current, "options": LEVELS}
    if error:
        payload["error"] = error
    print(json.dumps(payload))


async def config_get(url: str, connection_id: str, profile: str) -> int:
    try:
        async with gateway_ws(url, connection_id) as ws:
            current = await read_reasoning(ws, profile)
    except Exception as exc:
        emit_effort(False, effort_for(connection_id), str(exc))
        return 1
    current = current or "medium"
    remember_effort(connection_id, current)
    emit_effort(True, current)
    return 0


async def config_set(url: str, connection_id: str, profile: str, level: str) -> int:
    level = str(level or "").strip().lower()
    if level not in LEVELS:
        emit_effort(False, effort_for(connection_id), "invalid effort")
        return 2
    try:
        async with gateway_ws(url, connection_id) as ws:
            # No session_id: the gateway writes agent.reasoning_effort on the profile home.
            # scope=global keeps that write even when a stale session id is present.
            await write_reasoning(ws, level, profile, scope="global")
            current = await read_reasoning(ws, profile)
    except Exception as exc:
        emit_effort(False, effort_for(connection_id), str(exc))
        return 1
    current = current or level
    remember_effort(connection_id, current)
    emit_effort(True, current)
    return 0


def config_cli(argv: list[str]) -> int:
    cmd = argv[0]
    if cmd == "effort-for":
        if len(argv) < 2:
            return 2
        print(effort_for(argv[1]))
        return 0
    if cmd == "config-get":
        if len(argv) < 3:
            emit_effort(False, "", "usage: config-get <url> <connection_id> [profile]")
            return 2
        profile = argv[3] if len(argv) > 3 else ""
        return asyncio.run(config_get(argv[1], argv[2], profile))
    if cmd == "config-set":
        if len(argv) < 4:
            emit_effort(False, "", "usage: config-set <url> <connection_id> <profile> <level>")
            return 2
        return asyncio.run(config_set(argv[1], argv[2], argv[3], argv[4] if len(argv) > 4 else ""))
    return 2


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] in {"config-get", "config-set", "effort-for"}:
        return config_cli(sys.argv[1:])
    if len(sys.argv) < 5:
        print("usage: remote-send.py <url> <connection_id> <session> <prompt> [reasoning] [profile]", file=sys.stderr)
        return 2
    url, connection_id, session_name, prompt = sys.argv[1:5]
    reasoning = sys.argv[5] if len(sys.argv) > 5 else ""
    profile = sys.argv[6] if len(sys.argv) > 6 else ""
    try:
        return asyncio.run(run(url, connection_id, session_name, prompt, reasoning, profile))
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
