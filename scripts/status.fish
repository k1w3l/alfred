#!/usr/bin/env fish

set -l unit hermes-gateway.service
set -l state (systemctl --user is-active $unit 2>/dev/null)
set -l code $status

if test $code -eq 0; and test "$state" = active
  printf '{"active":true,"state":"active"}\n'
  exit 0
end

if test -z "$state"
  set state down
end

printf '{"active":false,"state":"%s"}\n' $state
exit 1
