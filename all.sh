#!/bin/sh


log() {
  # Echo the timestamp followed by the original message
  echo "[$(date "+%Y-%m-%dT%H:%M:%S%z")][all] - $1"
}
# Function to execute the script
execute_script() {
    script_path="https://elastic.github.io/kibana-demo-data/scripts/$1.sh"
    curl -fsSL "$script_path" | sh
}

# Function to search for a string in the array of arguments
search_string_in_args() {
    search=$1
    shift
    for arg in "$@"; do
        if [ "$arg" = "$search" ]; then
            return 0
        fi
    done
    return 1
}

show_help() {
  echo "Usage: $0 [options] [scripts]"
  echo
  echo "Options:"
  echo "  --help    Show this help message and exit"
  echo
  echo "Scripts:"
  echo "  custom    Install custom sample data (apache, nginx, kubernetes, etc)"
  echo "  o11y      Install o11y sample data"
  echo "  sample    Install Kibana sample data"
  echo "  security  Install security sample data"
  echo "  makelogs  Install makelogs sample data"
  echo
  echo "If no scripts are specified, all scripts will be executed."
}

# Show available scripts when --help is given
# Check for --help option
if [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# available scripts
scripts="custom o11y sample security makelogs"

if [ $# -eq 0 ]; then
    # execute all scripts
    log "Executing all scripts"
    for script in $scripts; do
        execute_script "$script"
    done
else
    # execute scripts based on arguments
    for script in $scripts; do

        if search_string_in_args "$script" "$@"; then
            log "Executing $script"
            execute_script "$script"
        fi
    done
fi

 log "Finished execution"

