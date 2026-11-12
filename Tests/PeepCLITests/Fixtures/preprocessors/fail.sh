#!/bin/sh
# Writes partial output and an error, exits 3.
echo 'partial output'
echo 'something went wrong' >&2
exit 3
