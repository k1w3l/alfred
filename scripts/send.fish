#!/usr/bin/env fish

set -gx PATH $HOME/.local/bin $HOME/.hermes/hermes-agent/venv/bin $PATH

set -l hermes hermes
if not command -q hermes
  set hermes $HOME/.hermes/hermes-agent/venv/bin/hermes
end

if not test -x $hermes
  echo "hermes CLI not found" >&2
  exit 127
end

set -l session hud
if test (count $argv) -ge 1; and test -n "$argv[1]"
  set session $argv[1]
end

set -l prompt
if test (count $argv) -ge 2
  set prompt (string join " " -- $argv[2..-1])
end

if test -z "$prompt"
  echo "empty prompt" >&2
  exit 2
end

cd $HOME
exec $hermes chat -Q --oneshot --accept-hooks \
  -c "$session" --create-if-missing \
  --source omarchy-hud \
  -q "$prompt"
