#!/usr/bin/env fish

set -l script_dir (dirname (status filename))
set -l py $HOME/.hermes/hermes-agent/venv/bin/python
if not test -x "$py"
  set py python3
end
exec $py -B $script_dir/sessions.py $argv
