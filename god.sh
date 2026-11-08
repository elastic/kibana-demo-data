#!/bin/sh
# Deprecated: god.sh was the original all-in-one installer. It now delegates to
# all.sh with the datasets it used to install, so the per-dataset scripts in
# scripts/ are the only ones that need maintaining.
set -eu

echo "god.sh is deprecated, use: curl -sSL https://elastic.github.io/kibana-demo-data | sh -s custom sample security o11y"

# Download first: in a plain `curl | sh` pipeline a download failure is invisible.
script=$(curl -fsSL https://elastic.github.io/kibana-demo-data/all.sh)
printf '%s\n' "$script" | sh -s custom sample security o11y
