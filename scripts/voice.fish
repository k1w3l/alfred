#!/usr/bin/env fish

# Alfred voice capture. start <wav> | stop <pid>
# start records with pw-record and prints LEVEL lines while samples arrive.

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH

set -l mode $argv[1]
set -l target $argv[2]
set -l here (status dirname)

if test "$mode" = start
  if test -z "$target"
    echo "missing wav path" >&2
    exit 2
  end
  exec python3 -B "$here/voice_capture.py" "$target"
end

if test "$mode" = stop
  if test -n "$target"; and test "$target" -gt 1
    kill -INT $target 2>/dev/null
    exit 0
  end
  echo "missing pid" >&2
  exit 2
end

echo "usage: voice.fish start <wav> | stop <pid>" >&2
exit 2
