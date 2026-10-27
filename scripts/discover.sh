#!/bin/sh
# Launch the adjacent module when checked out locally, or download it for curl | sh.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$script_dir/discover.mjs" ]; then
  exec node "$script_dir/discover.mjs" "$@"
fi

# Override to use a PR branch or another hosted copy of the scripts.
base_url="${KIBANA_DEMO_SCRIPTS_URL:-https://elastic.github.io/kibana-demo-data/scripts}"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
curl -fsSL "${base_url%/}/discover.mjs" -o "$tmp_dir/discover.mjs"
node "$tmp_dir/discover.mjs" "$@"
