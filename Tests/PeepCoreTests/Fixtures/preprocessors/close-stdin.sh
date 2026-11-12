#!/bin/sh
# Closes stdin before Peep has written it, so Peep's writes fail with EPIPE.
exec 0<&-
sleep 0.2
echo 'closed stdin'
