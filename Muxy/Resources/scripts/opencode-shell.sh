#!/bin/bash
if [[ -z "$1" ]]; then
  exec /opt/homebrew/bin/opencode
else
  exec /opt/homebrew/bin/opencode "$@"
fi