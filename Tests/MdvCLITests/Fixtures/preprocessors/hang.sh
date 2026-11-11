#!/bin/sh
# Hangs and ignores SIGTERM, so only SIGKILL stops it. Writes its pid to $1.
trap '' TERM
echo $$ > "$1"
while :; do sleep 1; done
