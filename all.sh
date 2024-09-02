#!/bin/sh

execute_script() {
    script_path="https://elastic.github.io/kibana-demo-data/scripts/$1.sh"
    curl "$script_path" | sh &
}

scripts="custom o11y sample security makelogs"

if [ $# -eq 0 ]; then
    for script in $scripts; do
        execute_script "$script"
    done
else
    for script in $scripts; do
        if search_string_in_args "$script" "$@"; then
            execute_script "$script"
        fi
    done
fi

wait

