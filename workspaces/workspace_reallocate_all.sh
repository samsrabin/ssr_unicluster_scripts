#!/bin/bash
set -e

if [[ $(ws_list | grep "id: tmp" | wc -l) -gt 0 ]]; then
    echo "tmp workspace already exists" >&2
    exit 1
fi

ws_list="$(ws_list | grep -E "^id:" | cut -d " " -f 2)"

# Set up temporary workspace
ws_allocate tmp 3
tmp_dir="$(ws_find tmp)"

for ws in ${ws_list}; do
    echo ${ws}...
    ws_dir="$(ws_find ${ws})"
    mv "${ws_dir}"/* "${tmp_dir}"/
    
    # Make sure it worked. Expect 2 files, . and ..
    if [[ $(ls -a ${ws_dir} | wc -l) -gt 2 ]]; then
        echo "File(s) remaining in ${ws_dir}!" >&2
        exit 1
    fi

    ws_release ${ws}
    ws_allocate ${ws} 999
    mv "${tmp_dir}"/* "${ws_dir}"/

    # Make sure it worked. Expect 2 files, . and ..
    if [[ $(ls -a ${tmp_dir} | wc -l) -gt 2 ]]; then
        echo "File(s) remaining in ${tmp_dir}!" >&2
        exit 1
    fi
done

ws_release tmp

exit 0
