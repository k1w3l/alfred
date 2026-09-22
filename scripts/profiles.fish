#!/usr/bin/env fish

# Hermes profiles — list / get / set (sticky + Alfred state).
# Modes: list | get | set <name>
# stdout: JSON

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH
set -gx HERMES_HOME $HOME/.hermes
set -gx PYTHONPATH $HOME/.hermes/hermes-agent

set -l script_dir (dirname (status filename))
set -l mode $argv[1]
if test -z "$mode"
  set mode list
end

set -l id ""
if test "$mode" = set
  set id $argv[2]
end

set -l py $HOME/.hermes/hermes-agent/venv/bin/python
if not test -x "$py"
  set py python3
end

exec $py $script_dir/profiles.py $mode $id
