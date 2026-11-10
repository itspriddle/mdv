#!/bin/sh
# Fails with stderr (CustomPreprocessorUITests).
cat > /dev/null
echo 'line 3: boom' >&2
exit 3
