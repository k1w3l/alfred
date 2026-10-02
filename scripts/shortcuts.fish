#!/usr/bin/env fish

set -l script_dir (dirname (status filename))
exec python3 -B $script_dir/shortcuts.py $argv
