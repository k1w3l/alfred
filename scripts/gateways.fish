#!/usr/bin/env fish

# Desktop-registered Hermes gateways (Settings → Gateways → connections.json).
# Modes: list | get | set <id>
# stdout: JSON {ok, current, connections:[{id,label,kind,url,...}]}

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH

set -l script_dir (dirname (status filename))
set -l mode $argv[1]
if test -z "$mode"
  set mode list
end

set -l id ""
if test "$mode" = set
  set id $argv[2]
end

exec python3 $script_dir/gateways.py $mode $id
