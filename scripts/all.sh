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

execute_script() {
    script_path="${script_dir}/$1.sh"
    echo "Executing $script_path"
    if [ -e "$script_path" ]; then
       sh "$script_path" &
    else
        echo "Error: $script_path is not executable. Skipping."
    fi
}

if [ $# -eq 0 ]; then
   echo "Executing all scripts"
   execute_script "custom"
   execute_script "search"
   execute_script "o11y"
   execute_script "security"
   execute_script "makelogs"
   wait
   exit 0
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

for script in "custom" "o11y" "security" "makelogs" "searchkit"; do
    if search_string_in_args "$script" "$@"; then
        execute_script "$script"
    fi
done

# Wait for all background processes to finish
wait;

