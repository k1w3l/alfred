#!/usr/bin/env fish

set -gx PATH \
  $HOME/.local/bin \
  $HOME/.cargo/bin \
  $HOME/.npm-global/bin \
  $HOME/.hermes/hermes-agent/venv/bin \
  $HOME/.hermes/bin \
  $HOME/.local/share/uv/tools/hermes/bin \
  $HOME/.local/share/pipx/venvs/hermes-agent/bin \
  /usr/local/bin \
  /usr/bin \
  $PATH

set -l hermes
if command -q hermes
  set hermes (command -v hermes)
end
if test -z "$hermes"
  for p in $HOME/.local/bin/hermes $HOME/.hermes/bin/hermes
    if test -x "$p"
      set hermes $p
      break
    end
  end
end
if test -z "$hermes"
  echo "{\"ok\":false,\"error\":\"hermes CLI not found\"}"
  exit 127
end

set -l mode $argv[1]
if test -z "$mode"
  set mode list
end

if test "$mode" = set
  set -l name $argv[2]
  if test -z "$name"
    echo "{\"ok\":false,\"error\":\"missing model\"}"
    exit 2
  end
  $hermes config set model.default $name >/dev/null
  and $hermes config get model --json
  exit $status
end

set -l current ($hermes config get model --json 2>/dev/null)
if test -z "$current"
  set current "{}"
end

printf '%s' $current | python3 -c '
import json, os, sys
current = json.loads(sys.stdin.read() or "{}")
provider = str(current.get("provider") or "")
name = str(current.get("default") or current.get("model") or "")
cache_path = os.path.expanduser("~/.hermes/provider_models_cache.json")
models = []
try:
    cache = json.load(open(cache_path))
    entry = cache.get(provider) if provider else None
    raw = entry.get("models") if isinstance(entry, dict) else None
    if isinstance(raw, list):
        for item in raw:
            mid = item if isinstance(item, str) else (item.get("id") if isinstance(item, dict) else "")
            if mid:
                models.append(mid)
except Exception:
    pass
if name and name not in models:
    models.insert(0, name)
print(json.dumps({"ok": True, "provider": provider, "current": name, "models": models}))
'
