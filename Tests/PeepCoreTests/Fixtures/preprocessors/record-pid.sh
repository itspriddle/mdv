#!/bin/sh
# Appends its pid to $1, then becomes the script $2 (same pid) with the remaining arguments,
# so a test knows exactly which processes it started.
log=$1
script=$2
shift 2
echo $$ >> "$log"
exec "$script" "$@"
