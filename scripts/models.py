#!/usr/bin/env python3
"""List / set Hermes model and provider for Alfred.

  models.py list
  models.py set <model>
  models.py set-provider <id>
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True

HOME = Path(os.path.expanduser("~"))
SCRIPT_DIR = Path(__file__).resolve().parent

PROVIDER_LABELS = {
    "openrouter": "OpenRouter",
    "openai-codex": "OpenAI Codex",
    "openai-api": "OpenAI",
    "xai-oauth": "xAI",
    "xai": "xAI",
    "opencode-go": "OpenCode Go",
    "opencode": "OpenCode Zen",
    "opencode-zen": "OpenCode Zen",
    "nous": "Nous Portal",
    "copilot": "GitHub Copilot",
    "copilot-acp": "Copilot ACP",
    "anthropic": "Anthropic",
}

PROVIDER_ENDPOINTS = {
    "openrouter": ("https://openrouter.ai/api/v1", "chat_completions"),
    "openai-codex": ("https://chatgpt.com/backend-api/codex", "codex_responses"),
    "openai-api": ("https://api.openai.com/v1", "codex_responses"),
    "xai-oauth": ("https://api.x.ai/v1", "codex_responses"),
    "xai": ("https://api.x.ai/v1", "codex_responses"),
    "opencode-go": ("https://opencode.ai/zen/go/v1", "chat_completions"),
    "nous": ("https://inference-api.nousresearch.com/v1", "chat_completions"),
    "copilot": ("https://api.githubcopilot.com", "chat_completions"),
}


def _load_profile_mod():
    import importlib.util

    path = SCRIPT_DIR / "alfred-profile.py"
    spec = importlib.util.spec_from_file_location("alfred_profile", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


alfred_profile = _load_profile_mod()


def hermes_bin() -> str:
    found = shutil.which("hermes")
    if found:
        return found
    for path in (HOME / ".local/bin/hermes", HOME / ".hermes/bin/hermes"):
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    return "hermes"


def profile_args() -> list[str]:
    name = alfred_profile.current_profile()
    if name and name != "default":
        return ["-p", name]
    return []


def hermes_run(args: list[str], *, check: bool = False) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    extra = [
        str(HOME / ".local/bin"),
        str(HOME / ".cargo/bin"),
        str(HOME / ".npm-global/bin"),
        str(HOME / ".hermes/hermes-agent/venv/bin"),
        str(HOME / ".hermes/bin"),
        "/usr/local/bin",
        "/usr/bin",
    ]
    env["PATH"] = os.pathsep.join(extra + [env.get("PATH", "")])
    return subprocess.run(
        [hermes_bin(), *profile_args(), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=30,
        check=check,
    )


def cache_path() -> Path:
    return alfred_profile.profile_home() / "provider_models_cache.json"


def load_cache() -> dict:
    try:
        raw = json.loads(cache_path().read_text(encoding="utf-8"))
        return raw if isinstance(raw, dict) else {}
    except Exception:
        return {}


def models_for(provider: str, cache: dict | None = None) -> list[str]:
    data = cache if cache is not None else load_cache()
    entry = data.get(provider) if provider else None
    raw = entry.get("models") if isinstance(entry, dict) else None
    out = []
    if isinstance(raw, list):
        for item in raw:
            mid = item if isinstance(item, str) else (item.get("id") if isinstance(item, dict) else "")
            if mid:
                out.append(str(mid))
    return out


def provider_label(provider: str) -> str:
    name = str(provider or "").strip()
    if not name:
        return "Provider"
    return PROVIDER_LABELS.get(name, name)


def current_model_block() -> dict:
    proc = hermes_run(["config", "get", "model", "--json"])
    text = (proc.stdout or "").strip()
    if not text:
        return {}
    try:
        parsed = json.loads(text)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def empty_error(message: str) -> dict:
    return {
        "ok": False,
        "error": message,
        "provider": "",
        "providerLabel": "",
        "current": "",
        "models": [],
        "providers": [],
    }


def dump_state() -> dict:
    block = current_model_block()
    provider = str(block.get("provider") or "").strip()
    name = str(block.get("default") or block.get("model") or "").strip()
    cache = load_cache()
    models = models_for(provider, cache)
    if name and name not in models:
        models.insert(0, name)
    seen = set()
    providers = []
    order = [provider] + [key for key in cache.keys() if key != provider]
    for pid in order:
        ident = str(pid or "").strip()
        if not ident or ident in seen:
            continue
        seen.add(ident)
        providers.append({"id": ident, "label": provider_label(ident), "checked": ident == provider})
    return {
        "ok": True,
        "provider": provider,
        "providerLabel": provider_label(provider) if provider else "",
        "current": name,
        "models": models,
        "providers": providers,
    }


def set_model(name: str) -> dict:
    ident = str(name or "").strip()
    if not ident:
        return empty_error("missing model")
    proc = hermes_run(["config", "set", "model.default", ident])
    if proc.returncode != 0:
        return empty_error((proc.stderr or proc.stdout or "config set failed").strip()[:240])
    return dump_state()


def set_provider(provider: str) -> dict:
    ident = str(provider or "").strip()
    if not ident:
        return empty_error("missing provider")
    models = models_for(ident)
    current = str(current_model_block().get("default") or "")
    if current not in models:
        current = models[0] if models else current
    proc = hermes_run(["config", "set", "model.provider", ident, "--force"])
    if proc.returncode != 0:
        proc = hermes_run(["config", "set", "model.provider", ident])
    if proc.returncode != 0:
        return empty_error((proc.stderr or proc.stdout or "provider set failed").strip()[:240])
    if current:
        hermes_run(["config", "set", "model.default", current, "--force"])
    endpoint = PROVIDER_ENDPOINTS.get(ident)
    if endpoint:
        hermes_run(["config", "set", "model.base_url", endpoint[0], "--force"])
        hermes_run(["config", "set", "model.api_mode", endpoint[1], "--force"])
    else:
        hermes_run(["config", "unset", "model.base_url"])
        hermes_run(["config", "unset", "model.api_mode"])
    return dump_state()


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    if mode == "set":
        payload = set_model(sys.argv[2] if len(sys.argv) > 2 else "")
    elif mode in ("set-provider", "provider"):
        payload = set_provider(sys.argv[2] if len(sys.argv) > 2 else "")
    else:
        payload = dump_state()
    print(json.dumps(payload, ensure_ascii=False))
    return 0 if payload.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
