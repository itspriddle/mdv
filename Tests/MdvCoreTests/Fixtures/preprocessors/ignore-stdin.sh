#!/bin/sh
# Never reads stdin; answers after a moment (while mdv's write to stdin is blocked).
sleep 0.2
echo 'ignored stdin'
