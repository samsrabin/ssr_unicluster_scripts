#!/bin/bash
set -euo pipefail

# This script takes all your workspaces (as given by ws_list) and moves them to new workspaces with the same names

if [[ $(ws_list | grep "id: tmp" | wc -l) -gt 0 ]]; then
    echo "tmp workspace already exists" >&2
    exit 1
fi

echo ===BEFORE===
ws_list
echo -e "\n\n\n"

ws_list="$(ws_list | grep -E "^id:" | cut -d " " -f 2)"

# Set up temporary workspace
ws_allocate tmp 3
tmp_dir="$(ws_find tmp)"

for ws in ${ws_list}; do
    echo ${ws}...
    ws_dir="$(ws_find ${ws})"
    echo "   Moving to '${tmp_dir}/'..."
    mv "${ws_dir}"/* "${tmp_dir}"/
    
    # Make sure it worked. Expect 0 files
    if [[ $(ls -A ${ws_dir} || true | wc -l) -gt 0 ]]; then
        echo "File(s) remaining in ${ws_dir}!" >&2
        exit 1
    fi

    echo "   Releasing existing workspace..."
    ws_release ${ws}
    echo "   Allocating new workspace..."
    ws_allocate ${ws} 999
    echo "   Moving to new workspace from tmp dir..."
    mv "${tmp_dir}"/* "${ws_dir}"/

    # Make sure it worked. Expect 0 files
    if [[ $(ls -A ${tmp_dir} || true | wc -l) -gt 0 ]]; then
        echo "File(s) remaining in ${tmp_dir}!" >&2
        exit 1
    fi

    echo "   Done!"
done

echo "Releasing tmp workspace..."
ws_release tmp

echo "All done!"

echo -e "\n\n\n===AFTER==="
ws_list

exit 0
