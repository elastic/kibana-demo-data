#!/bin/sh

script_dir=$(dirname "$0")

# Function to kill all child processes
cleanup() {
    echo "Terminating all child processes..."
    pkill -P $$
    wait
    exit 0
}

# Trap SIGINT (Ctrl-C) and call the cleanup function
trap cleanup 2

jobs_started=""
execute_script() {
    script_path="${script_dir}/$1.sh"
    echo "Executing $script_path"
    if [ -e "$script_path" ]; then
       sh "$script_path" &
       # Remember "pid:name" so wait_all can report which script failed.
       jobs_started="$jobs_started $!:$1"
    else
        echo "Error: $script_path not found. Skipping."
    fi
}

# Wait for every started script; a bare `wait` would discard their exit codes.
wait_all() {
    failed=""
    for job in $jobs_started; do
        if ! wait "${job%%:*}"; then
            failed="$failed ${job#*:}"
        fi
    done
    if [ -n "$failed" ]; then
        echo "Finished with failures:$failed"
        return 1
    fi
    return 0
}

if [ $# -eq 0 ]; then
   echo "Executing all scripts"
   execute_script "custom"
   execute_script "search"
   execute_script "o11y"
   execute_script "sample"
   execute_script "security"
   execute_script "makelogs"
   execute_script "discover"
   wait_all
   exit $?
fi

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

for script in "custom" "o11y" "sample" "security" "makelogs" "searchkit" "discover"; do
    if search_string_in_args "$script" "$@"; then
        execute_script "$script"
    fi
done

# Wait for all background processes to finish
wait_all
exit $?
