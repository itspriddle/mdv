#!/bin/sh
# Reports what it was started with: arguments, working directory, environment, open fds.
for argument in "$@"; do printf 'arg=%s\n' "$argument"; done
printf 'pwd=%s\n' "$(pwd -P)"
env | LC_ALL=C sort | sed 's/^/env=/'
for fd in /dev/fd/*; do printf 'fd=%s\n' "${fd#/dev/fd/}"; done
cat > /dev/null
