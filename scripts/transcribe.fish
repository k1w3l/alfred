#!/usr/bin/env fish

# Transcribe a WAV with Voxtype (the model in ~/.config/voxtype/config.toml).
# stdout: JSON {success, transcript, error?, provider, model}

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH

set -l wav $argv[1]
if test -z "$wav"
  echo '{"success":false,"transcript":"","error":"missing wav","provider":"voxtype"}'
  exit 2
end

set -l here (status dirname)
exec python3 -B "$here/transcribe.py" "$wav"
