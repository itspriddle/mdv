#!/bin/sh
# Writes far more stderr than mdv keeps, ending with a known line, then exits 1.
i=0
while [ $i -lt 4000 ]; do echo "noise line $i of the stderr flood" >&2; i=$((i + 1)); done
echo 'the last line' >&2
exit 1
