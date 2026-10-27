#!/bin/sh
# Launch the adjacent module when checked out locally, or stream it into Node for curl | sh.
set -eu

# Under curl | sh, $0 is the shell, not a path to this launcher. Never
# execute a discover.mjs found in the caller's working directory in that case.
case "$0" in
  */discover.sh|discover.sh)
    script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    if [ -f "$script_dir/discover.mjs" ]; then
      exec node "$script_dir/discover.mjs" "$@"
    fi
    ;;
esac

# Override to use a PR branch or another hosted copy of the scripts.
base_url="${KIBANA_DEMO_SCRIPTS_URL:-https://elastic.github.io/kibana-demo-data/scripts}"
# Bash's pipefail makes a failed curl fail the launcher too, even if Node
# receives empty input and exits successfully. No JavaScript file is saved.
exec bash -o pipefail -c '
  curl --proto "=https" --proto-redir "=https" -fsSL "$1" | node --input-type=module - "${@:2}"
' discover "${base_url%/}/discover.mjs" "$@"
