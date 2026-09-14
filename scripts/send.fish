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

set -l session alfred
if test (count $argv) -ge 1; and test -n "$argv[1]"
  set session $argv[1]
end

set -l prompt
if test (count $argv) -ge 2
  set prompt (string join " " -- $argv[2..-1])
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

cd $HOME
exec $hermes chat -Q --oneshot --accept-hooks \
  -c "$session" --create-if-missing \
  --source alfred \
  -q "$prompt"
