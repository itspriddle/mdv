#!/bin/sh
# Writes to stderr, then dies by SIGSEGV.
ulimit -c 0
echo 'about to crash' >&2
kill -SEGV $$
