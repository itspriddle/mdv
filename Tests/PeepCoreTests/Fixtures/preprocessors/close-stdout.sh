#!/bin/sh
# Writes partial output and closes stdout early. With $1 = "exit" it then exits 0;
# otherwise it keeps running.
printf 'partial'
exec 1>&-
if [ "$1" = exit ]; then exit 0; fi
sleep 30
