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

set -l script_dir (dirname (status filename))
exec python3 -B $script_dir/models.py $argv
