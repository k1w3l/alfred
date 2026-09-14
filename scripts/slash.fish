#!/usr/bin/env fish

# Slash catalog / completions — same sources as Hermes Desktop (commands + skills).
# argv[1]: composer text (default "/")
# stdout: JSON {ok, items:[{text,display,meta,group,kind}], query}

set -gx PATH /usr/bin /usr/local/bin $HOME/.local/bin $PATH
set -gx HERMES_HOME $HOME/.hermes
set -gx VIRTUAL_ENV $HOME/.hermes/hermes-agent/venv
set -gx PYTHONPATH $HOME/.hermes/hermes-agent

set -l py $HOME/.hermes/hermes-agent/venv/bin/python
if not test -x "$py"
    echo '{"ok":false,"items":[],"query":"","error":"hermes venv missing"}'
    exit 127
end

set -l dir (dirname (status filename))
set -l text $argv[1]
if test -z "$text"
    set text /
end

cd $HOME/.hermes
exec $py $dir/slash.py $text
