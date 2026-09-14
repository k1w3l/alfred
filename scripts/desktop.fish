#!/usr/bin/env fish

set -gx PATH \
  $HOME/.local/bin \
  $HOME/.cargo/bin \
  $HOME/.hermes/hermes-agent/venv/bin \
  $HOME/.hermes/bin \
  /usr/local/bin \
  /usr/bin \
  $PATH

if command -q hermes-desktop
  exec hermes-desktop
end

set -l desktop $HOME/.local/bin/hermes-desktop
if test -x $desktop
  exec $desktop
end

if command -q hermes
  exec hermes desktop
end

set -l from_login (bash -lc 'command -v hermes-desktop || command -v hermes' 2>/dev/null)
if test -n "$from_login"; and test -x "$from_login"
  if string match -q '*hermes-desktop' $from_login
    exec $from_login
  end
  exec $from_login desktop
end

echo "hermes-desktop not found" >&2
exit 127
