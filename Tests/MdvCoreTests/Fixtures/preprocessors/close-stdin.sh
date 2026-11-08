#!/bin/sh
# Closes stdin before mdv has written it, so mdv's writes fail with EPIPE.
exec 0<&-
sleep 0.2
echo 'closed stdin'
