#!/usr/bin/env fish

# Reasoning effort for the selected Hermes gateway.
# Local: hermes config agent.reasoning_effort.
# Remote: config.set {key: reasoning, scope: global} on that profile, no session id.
# Modes: list | get | set <level>
# stdout: JSON

set -gx PATH \
  $HOME/.local/bin \
  $HOME/.cargo/bin \
  $HOME/.npm-global/bin \
  $HOME/.hermes/hermes-agent/venv/bin \
  $HOME/.hermes/bin \
  /usr/local/bin \
  /usr/bin \
  $PATH

set -l script_dir (dirname (status filename))
set -l mode $argv[1]
if test -z "$mode"
  set mode list
end

set -l levels none minimal low medium high xhigh max ultra
set -l level ""
if test "$mode" = set
  set level (string lower -- (string trim -- $argv[2]))
  if test -z "$level"
    echo '{"ok":false,"error":"missing effort","current":"","options":[]}'
    exit 2
  end
  set -l ok 0
  for l in $levels
    if test "$l" = "$level"
      set ok 1
      break
    end
  end
  if test $ok -eq 0
    echo '{"ok":false,"error":"invalid effort","current":"","options":[]}'
    exit 2
  end
end

set -l gw (python3 -B $script_dir/gateways.py get 2>/dev/null)
set -l kind local
set -l url ""
set -l conn_id local
if test -n "$gw"
  set kind (printf '%s' $gw | python3 -B -c 'import json,sys; d=json.load(sys.stdin); print(d.get("kind") or "local")' 2>/dev/null)
  set url (printf '%s' $gw | python3 -B -c 'import json,sys; d=json.load(sys.stdin); print(d.get("url") or "")' 2>/dev/null)
  set conn_id (printf '%s' $gw | python3 -B -c 'import json,sys; d=json.load(sys.stdin); print(d.get("current") or "local")' 2>/dev/null)
end

if test "$kind" != local; and test -n "$url"
  set -l py $HOME/.hermes/hermes-agent/venv/bin/python
  if not test -x "$py"
    set py python3
  end
  set -l profile_name (python3 -B $script_dir/alfred-profile.py name 2>/dev/null)
  if test "$mode" = set
    exec $py -B $script_dir/remote-send.py config-set "$url" "$conn_id" "$profile_name" "$level"
  end
  exec $py -B $script_dir/remote-send.py config-get "$url" "$conn_id" "$profile_name"
end

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
  echo '{"ok":false,"error":"hermes CLI not found","current":"","options":[]}'
  exit 127
end

set -l profile_args
set -l profile_name (python3 -B $script_dir/alfred-profile.py name 2>/dev/null)
if test -n "$profile_name"; and test "$profile_name" != default
  set profile_args -p $profile_name
end

if test "$mode" = set
  $hermes $profile_args config set agent.reasoning_effort $level --force >/dev/null 2>&1
  or begin
    echo '{"ok":false,"error":"config set failed","current":"","options":[]}'
    exit 1
  end
end

set -l current ($hermes $profile_args config get agent.reasoning_effort 2>/dev/null | string trim)
set current (string lower -- $current)
set current (string trim -c '"' -- $current)
if test -z "$current"
  set current medium
end

env LEVEL=$current python3 -B -c '
import json, os
from pathlib import Path
p = Path(os.path.expanduser("~/.config/Hermes/alfred.json"))
data = {}
try:
    data = json.loads(p.read_text())
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
data["reasoningEffort"] = os.environ.get("LEVEL") or ""
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2) + "\n")
'

python3 -B -c '
import json, sys
current = sys.argv[1]
options = ["none","minimal","low","medium","high","xhigh","max","ultra"]
print(json.dumps({"ok": True, "current": current, "options": options}))
' "$current"
