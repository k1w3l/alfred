#!/usr/bin/env fish

# Alfred voice capture. start <wav> | stop <pid>
# Uses pw-record when PipeWire is available.

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH

set -l mode $argv[1]
set -l target $argv[2]

if test "$mode" = start
  if test -z "$target"
    echo "missing wav path" >&2
    exit 2
  end
  if command -q pw-record
    exec pw-record --rate 16000 --channels 1 "$target"
  end
  if command -q parecord
    exec parecord --rate=16000 --channels=1 "$target"
  end
  echo "pw-record not found" >&2
  exit 127
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
