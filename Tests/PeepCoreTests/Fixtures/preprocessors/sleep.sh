#!/bin/sh
# Sleeps past any test timeout (SIGTERM stops it). Writes its pid to $1.
echo $$ > "$1"
sleep 30
