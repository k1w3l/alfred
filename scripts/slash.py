#!/usr/bin/env python3
"""Slash catalog and completions for the Alfred HUD.

Bare `/` matches Hermes Desktop: categorized `commands.catalog` plus leftover
Skills. Typing after `/` uses the same SlashCommandCompleter as `complete.slash`.
"""

from __future__ import annotations

import json
import os
import re
import sys
from typing import Any

os.environ.setdefault("HERMES_HOME", os.path.expanduser("~/.hermes"))

SLASH_TOKEN = re.compile(r"(?:^|\s)(/[^\s]*)$")


def _plain(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    try:
        from prompt_toolkit.formatted_text import to_plain_text

        return to_plain_text(value) or ""
    except Exception:
        return str(value)


def command_text(raw: str) -> str:
    token = str(raw or "").strip()
    if not token:
        return ""
    if not token.startswith("/"):
        token = "/" + token
    return token.split()[0]


def last_slash_token(text: str) -> str | None:
    match = SLASH_TOKEN.search(str(text or ""))
    return match.group(1) if match else None


def _skill_names() -> set[str]:
    names: set[str] = set()
    try:
        from agent.skill_commands import get_skill_commands

        names.update(key.lstrip("/").lower() for key in (get_skill_commands() or {}))
    except Exception:
        pass
    try:
        from agent.skill_bundles import get_skill_bundles

        names.update(key.lstrip("/").lower() for key in (get_skill_bundles() or {}))
    except Exception:
        pass
    return names


def _item(text: str, meta: str, group: str, kind: str, display: str = "") -> dict[str, str]:
    cmd = command_text(text)
    return {
        "text": cmd,
        "display": display or cmd,
        "meta": str(meta or "").replace("\n", " ").strip()[:160],
        "group": group,
        "kind": kind,
    }


def catalog_items() -> list[dict[str, str]]:
    """Desktop bare-`/` list: registry categories, then leftover Skills."""
    items: list[dict[str, str]] = []
    seen: set[str] = set()

    try:
        from hermes_cli.commands import COMMAND_REGISTRY, _build_description

        for cmd in COMMAND_REGISTRY:
            if getattr(cmd, "gateway_only", False):
                continue
            key = f"/{cmd.name}"
            seen.add(key.lower())
            items.append(
                _item(
                    key,
                    _build_description(cmd),
                    str(getattr(cmd, "category", "") or "Commands"),
                    "command",
                )
            )
    except Exception:
        pass

    try:
        from hermes_cli.config import load_config

        cfg = load_config() or {}
        qcmds = cfg.get("quick_commands") or {}
        if isinstance(qcmds, dict):
            for qname, qc in sorted(qcmds.items()):
                if not isinstance(qc, dict):
                    continue
                key = f"/{qname}"
                if key.lower() in seen:
                    continue
                seen.add(key.lower())
                qtype = qc.get("type", "")
                if qtype == "exec":
                    default = f"exec: {qc.get('command', '')}"
                elif qtype == "alias":
                    default = f"alias → {qc.get('target', '')}"
                else:
                    default = qtype or "quick command"
                desc = str(qc.get("description") or default)
                items.append(_item(key, desc, "User commands", "command"))
    except Exception:
        pass

    try:
        from hermes_cli.plugins import get_plugin_commands

        plugin_cmds = get_plugin_commands() or {}
        for pname, info in sorted(plugin_cmds.items()):
            if not isinstance(info, dict):
                continue
            key = f"/{pname}"
            if key.lower() in seen:
                continue
            seen.add(key.lower())
            items.append(
                _item(key, str(info.get("description") or "Plugin command"), "Plugin commands", "command")
            )
    except Exception:
        pass

    try:
        from agent.skill_commands import scan_skill_commands

        for key, info in sorted((scan_skill_commands() or {}).items()):
            if str(key).lower() in seen:
                continue
            desc = str((info or {}).get("description") or "Skill")
            items.append(_item(str(key), desc, "Skills", "skill"))
    except Exception:
        pass

    return items


def complete_items(text: str) -> list[dict[str, str]]:
    from hermes_cli.commands import SlashCommandCompleter
    from prompt_toolkit.document import Document

    from agent.skill_bundles import get_skill_bundles
    from agent.skill_commands import get_skill_commands

    completer = SlashCommandCompleter(
        skill_commands_provider=lambda: get_skill_commands(),
        skill_bundles_provider=lambda: get_skill_bundles(),
    )
    skills = _skill_names()
    doc = Document(text, len(text))
    raw: list[dict[str, str]] = []
    for completion in completer.get_completions(doc, None):
        cmd = command_text(completion.text)
        if not cmd:
            continue
        name = cmd.lstrip("/").lower()
        kind = "skill" if name in skills else "command"
        group = "Skills" if kind == "skill" else "Commands"
        display = _plain(completion.display) or cmd
        meta = _plain(completion.display_meta)
        raw.append(_item(cmd, meta, group, kind, display=display if display.startswith("/") else cmd))

    query = last_slash_token(text) or text
    if " " not in text.strip() and len(query) > 1:
        try:
            from tui_gateway.slash_fuzzy import fuzzy_rank_slash_items, normalize_slash_search_query

            universe = complete_universe(completer, skills)
            ranked, _score = fuzzy_rank_slash_items(raw, universe, normalize_slash_search_query(query))
            raw = ranked
        except Exception:
            pass

    normalized: list[dict[str, str]] = []
    for item in raw:
        cmd = command_text(str(item.get("text") or ""))
        if not cmd:
            continue
        name = cmd.lstrip("/").lower()
        kind = str(item.get("kind") or ("skill" if name in skills else "command"))
        group = "Skills" if kind == "skill" else "Commands"
        normalized.append(
            _item(cmd, str(item.get("meta") or ""), group, kind, display=str(item.get("display") or cmd))
        )
    order = {"Commands": 0, "Skills": 1}
    normalized.sort(key=lambda item: order.get(item["group"], 2))
    return normalized


def complete_universe(completer: Any, skills: set[str]) -> list[dict[str, str]]:
    from prompt_toolkit.document import Document

    universe: list[dict[str, str]] = []
    for completion in completer.get_completions(Document("/", 1), None):
        cmd = command_text(completion.text)
        if not cmd:
            continue
        name = cmd.lstrip("/").lower()
        kind = "skill" if name in skills else "command"
        universe.append(
            {
                "text": cmd,
                "display": _plain(completion.display) or cmd,
                "meta": _plain(completion.display_meta),
                "kind": kind,
            }
        )
    return universe


def main() -> int:
    text = sys.argv[1] if len(sys.argv) > 1 else "/"
    if text == "":
        text = "/"
    query = last_slash_token(text)
    try:
        if query is None:
            items: list[dict[str, str]] = []
        elif query == "/":
            items = catalog_items()
        else:
            items = complete_items(text)
        print(json.dumps({"ok": True, "items": items, "query": query or ""}, ensure_ascii=False))
        return 0
    except Exception as exc:
        print(json.dumps({"ok": False, "items": [], "query": query or "", "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
