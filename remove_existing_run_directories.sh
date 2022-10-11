#!/bin/bash
set -e

# Clear existing run* directories
set +e
ls -d run*/ 1> /dev/null 2>&1
result=$?
set -e

if [[ $result == 0 ]]; then
    empty_dir="empty_dir_$(date +%N)/"
    mkdir $empty_dir
    echo "Removing existing run*/ directories..."
    for d in $(ls -d run*/ | grep -E "^run[0-9]+/"); do
        rsync -a --delete $empty_dir $d/
        rmdir $d
    done
    rmdir $empty_dir
fi

exit 0
