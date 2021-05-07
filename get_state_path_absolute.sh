#!/bin/bash

rundir_top="$1"
state_path_absolute="$2"

# If already exists, don't mess with it
if [[ "${state_path_absolute}" != "" ]]; then
    echo $state_path_absolute
    exit 0
fi

periodname=$(basename "${rundir_top}")

state_path_absolute=$(echo $rundir_top | sed "s@${periodname}@states@")

echo $state_path_absolute

exit 0
