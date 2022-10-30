#!/bin/bash

rundir_top="$1"
state_path_absolute="$2"
dev="$3"
if [[ "${dev}" == "" ]]; then
    echo "g2p_get_state_path_absolute.sh: You must provide rundir_top, state_path_absolute, and dev" >&2
    exit 1
fi

# If already exists, don't mess with it
if [[ "${state_path_absolute}" != "" ]]; then
    echo $state_path_absolute
    exit 0
fi

periodname=$(basename "${rundir_top}")

# Relies on $periodname only being found once in $rundir_top (at the end)
state_path_absolute=$(echo $rundir_top | sed "s@${periodname}@states@")

if [[ ${dev} ]]; then
    state_path_absolute+="_test"
fi

echo $state_path_absolute

exit 0
