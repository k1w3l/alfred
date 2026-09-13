#!/usr/bin/env fish

set -gx PATH $HOME/.local/bin $HOME/.hermes/hermes-agent/venv/bin $PATH

set -l desktop hermes-desktop
if command -q hermes-desktop
  exec hermes-desktop
end

if command -q hermes
  exec hermes desktop
end

echo "hermes-desktop not found" >&2
exit 127
