#!/usr/bin/env fish

# Profiles across the local gateway and remote Desktop gateways.
# Modes: list | set <gateway:profile> | face <key> <shape> <fill> <expression> [idle] | face-reset <key>
# stdout: JSON

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH
set -gx HERMES_HOME $HOME/.hermes
set -gx PYTHONPATH $HOME/.hermes/hermes-agent

set -l script_dir (dirname (status filename))

set -l py $HOME/.hermes/hermes-agent/venv/bin/python
if not test -x "$py"
  set py python3
end

exec $py -B $script_dir/roster.py $argv
