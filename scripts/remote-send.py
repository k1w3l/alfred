#!/usr/bin/env python3
"""Send a oneshot prompt to a remote Hermes Desktop gateway over WebSocket RPC."""

from __future__ import annotations

import asyncio
import json
import os
import sys
import urllib.parse
from http.cookiejar import CookieJar
from pathlib import Path
from typing import Any

import httpx
import websockets

HOME = Path(os.path.expanduser("~"))
AUTH_PATH = HOME / ".config" / "Hermes" / "alfred-auth.json"
STATE_PATH = HOME / ".config" / "Hermes" / "alfred.json"


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def auth_for(connection_id: str) -> dict:
    data = load_json(AUTH_PATH, {})
    entry = data.get(connection_id) if isinstance(data, dict) else None
    return entry if isinstance(entry, dict) else {}


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


async def collect_reply(ws, session_id: str, timeout: float = 600.0) -> str:
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
        if method and msg.get("id") and "result" not in msg:
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
        if method == "message.delta":
            if str(params.get("session_id") or "") in ("", session_id):
                text = params.get("text") or params.get("delta") or ""
                if text:
                    chunks.append(str(text))
                    sys.stdout.write(str(text))
                    sys.stdout.flush()
        elif method in ("message.complete", "message.done"):
            if str(params.get("session_id") or "") in ("", session_id):
                final = params.get("text") or params.get("content") or "".join(chunks)
                if final and not chunks:
                    sys.stdout.write(str(final))
                    sys.stdout.flush()
                return str(final or "".join(chunks))
        elif method in ("error", "session.error"):
            raise RuntimeError(str(params.get("message") or params or "remote error"))


async def run(url: str, connection_id: str, session_name: str, prompt: str, reasoning: str, profile: str = "") -> int:
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
            # Wait briefly for gateway.ready
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=5)
                msg = json.loads(raw)
                if msg.get("method") == "gateway.ready":
                    await rpc(ws, "client.capabilities", {"server_requests": True}, timeout=10)
            except Exception:
                pass

            created = await rpc(
                ws,
                "session.create",
                {
                    "title": session_name or "alfred",
                    "source": "alfred",
                    **({"profile": profile} if profile and profile != "default" else {}),
                },
                timeout=30,
            )
            session_id = ""
            if isinstance(created, dict):
                session_id = str(created.get("session_id") or created.get("id") or "")
            if not session_id:
                raise RuntimeError(f"session.create returned no id: {created}")

            if reasoning:
                try:
                    await rpc(ws, "config.set", {"key": "reasoning", "session_id": session_id, "value": reasoning}, timeout=15)
                except Exception:
                    pass

            await rpc(ws, "prompt.submit", {"session_id": session_id, "text": prompt}, timeout=30)
            await collect_reply(ws, session_id)
    return 0


def main() -> int:
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
