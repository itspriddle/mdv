#!/bin/sh
# Starts a child that hangs (ignoring SIGTERM, holding stdout), writes both pids to $1,
# then waits for the child. If $2 is "exit", exits 0 right away instead, leaving the child.
sh -c 'trap "" TERM; while :; do sleep 1; done' &
echo "$$ $!" > "$1"
if [ "$2" = exit ]; then
  sleep 0.1 # let the child set its trap first
  echo done
  exit 0
fi
wait
