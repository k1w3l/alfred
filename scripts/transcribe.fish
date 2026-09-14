#!/usr/bin/env fish

# Transcribe a WAV via Hermes STT (same pipeline as Desktop voice mode).
# stdout: JSON {success, transcript, error?}

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH
set -gx HERMES_HOME $HOME/.hermes
set -gx VIRTUAL_ENV $HOME/.hermes/hermes-agent/venv
set -gx PYTHONPATH $HOME/.hermes/hermes-agent

set -l wav $argv[1]
if test -z "$wav"; or not test -f "$wav"
  echo '{"success":false,"transcript":"","error":"missing wav"}'
  exit 2
end

set -l py $HOME/.hermes/hermes-agent/venv/bin/python
if not test -x "$py"
  echo '{"success":false,"transcript":"","error":"hermes venv missing"}'
  exit 127
end

cd $HOME/.hermes
exec $py -c '
import json, sys
from tools.voice_mode import transcribe_recording
path = sys.argv[1]
try:
    result = transcribe_recording(path)
except Exception as exc:
    result = {"success": False, "transcript": "", "error": str(exc)}
if not isinstance(result, dict):
    result = {"success": False, "transcript": str(result), "error": ""}
print(json.dumps(result))
' "$wav"
