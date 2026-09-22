#!/usr/bin/env fish

# Gateway health for the currently selected Alfred connection.
# Local → systemd hermes-gateway.service
# Remote → GET {url}/api/status

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH
set -l script_dir (dirname (status filename))

set -l info (python3 $script_dir/gateways.py get 2>/dev/null)
if test -z "$info"
  # Fallback to classic local check
  set -l unit hermes-gateway.service
  set -l state (systemctl --user is-active $unit 2>/dev/null)
  if test $status -eq 0; and test "$state" = active
    printf '{"active":true,"state":"active"}\n'
    exit 0
  end
  if test -z "$state"
    set state down
  end
  printf '{"active":false,"state":"%s"}\n' $state
  exit 1
end

printf '%s' $info | python3 -c '
import json, sys
d = json.load(sys.stdin)
kind = d.get("kind") or "local"
running = bool(d.get("gateway_running"))
reachable = bool(d.get("reachable"))
label = d.get("label") or d.get("current") or "local"
if kind == "local":
    active = running
    state = "active" if active else "down"
else:
    active = reachable and running
    if not reachable:
        state = "unreachable"
    elif running:
        state = "active"
    else:
        state = "down"
print(json.dumps({"active": active, "state": state, "label": label, "kind": kind}))
sys.exit(0 if active else 1)
'
