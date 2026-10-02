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

set -l candidates
if command -q hermes
  set -a candidates (command -v hermes)
end
set -a candidates \
  $HOME/.local/bin/hermes \
  $HOME/.cargo/bin/hermes \
  $HOME/.hermes/hermes-agent/venv/bin/hermes \
  $HOME/.hermes/bin/hermes \
  $HOME/.local/share/uv/tools/hermes/bin/hermes \
  $HOME/.local/share/pipx/venvs/hermes-agent/bin/hermes

set -l hermes
for p in $candidates
  if test -n "$p"; and test -x "$p"
    set hermes $p
    break
  end
end

if test -z "$hermes"
  set -l from_login (bash -lc 'command -v hermes' 2>/dev/null)
  if test -n "$from_login"; and test -x "$from_login"
    set hermes $from_login
  end
end

if test -z "$hermes"
  echo "hermes CLI not found" >&2
  exit 127
end

# Session ref: "id:<session_id>" resumes by id, "" starts a fresh session,
# anything else resumes (or creates) the session with that title.
set -l session ""
if test (count $argv) -ge 1
  set session $argv[1]
end

set -l prompt
if test (count $argv) -ge 2
  set prompt (string join " " -- $argv[2..-1])
end

# Optional trailing file paths after a -- separator are not used; Service passes
# files as trailing argv. Reconstruct: session, prompt, then files.
# When called as: send.fish SESSION PROMPT [files...]
# the prompt is argv[2] only (single arg). Keep that contract.
if test (count $argv) -ge 2
  set prompt $argv[2]
end

if test -z "$prompt"; and not isatty stdin
  set prompt (cat)
end

set -l files
if test (count $argv) -ge 3
  set files $argv[3..-1]
end

if set -q ALFRED_FILES; and test -n "$ALFRED_FILES"
  for f in (string split \n -- $ALFRED_FILES)
    if test -n "$f"
      set -a files $f
    end
  end
end

if test (count $files) -gt 0
  set -l listing
  for f in $files
    set listing $listing \n- $f
  end
  if test -z "$prompt"
    set prompt "Use the attached files as context."
  end
  set prompt "Attached files (absolute paths):"$listing\n\n$prompt
end

if test -z "$prompt"
  echo "empty prompt" >&2
  exit 2
end

set -l reasoning ""
if set -q ALFRED_REASONING; and test -n "$ALFRED_REASONING"
  set reasoning $ALFRED_REASONING
else
  set reasoning (python3 -c '
import json, os
from pathlib import Path
p = Path(os.path.expanduser("~/.config/Hermes/alfred.json"))
try:
    d = json.loads(p.read_text())
    print(str(d.get("reasoningEffort") or "").strip())
except Exception:
    print("")
' 2>/dev/null)
end
if test -z "$reasoning"
  set reasoning ($hermes config get agent.reasoning_effort 2>/dev/null | string trim -c '"' | string trim)
end

set -l script_dir (dirname (status filename))
set -l gw (python3 $script_dir/gateways.py get 2>/dev/null)
set -l kind local
set -l url ""
set -l conn_id local
if test -n "$gw"
  set kind (printf '%s' $gw | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("kind") or "local")' 2>/dev/null)
  set url (printf '%s' $gw | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("url") or "")' 2>/dev/null)
  set conn_id (printf '%s' $gw | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("current") or "local")' 2>/dev/null)
end

if test "$kind" != local; and test -n "$url"
  set -l py $HOME/.hermes/hermes-agent/venv/bin/python
  if not test -x "$py"
    set py python3
  end
  cd $HOME
  set -l profile_name (python3 $script_dir/alfred-profile.py name 2>/dev/null)
  set -l remote_title (string replace -r '^id:' '' -- $session)
  if test -z "$remote_title"
    set remote_title alfred
  end
  exec $py $script_dir/remote-send.py "$url" "$conn_id" "$remote_title" "$prompt" "$reasoning" "$profile_name"
end

set -l reasoning_args
if test -n "$reasoning"
  set reasoning_args --reasoning $reasoning
end

cd $HOME
set -l profile_args
set -l profile_name (python3 $script_dir/alfred-profile.py name 2>/dev/null)
if test -n "$profile_name"; and test "$profile_name" != default
  set profile_args -p $profile_name
end
set -l session_args
if string match -q 'id:*' -- $session
  set session_args --resume (string replace -r '^id:' '' -- $session)
else if test -n "$session"
  set session_args -c "$session" --create-if-missing
end
exec $hermes $profile_args chat --format stream-json --oneshot --accept-hooks \
  $session_args \
  --source alfred \
  $reasoning_args \
  -q "$prompt"
