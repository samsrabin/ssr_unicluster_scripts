#!/bin/bash
set -e

# Make sure old workspace exists
ws1=$1
if [[ ${ws1} == "" ]]; then
    echo "You must provide old workspace name!"
    exit 1
fi
ws1_path=$(ws_find ${ws1})
if [[ ${ws1_path} == "" ]]; then
    echo "Workspace ${ws1} not found!"
    exit 1
fi

# Make sure new workspace exists
ws2=${2}
if [[ ${ws2} == "" ]]; then
    echo "You must provide new workspace name!"
    exit 1
fi
ws2_path=$(ws_find ${ws2})
if [[ ${ws2_path} == "" ]]; then
    echo "Workspace ${ws2} not found!"
    exit 1
fi

# Do the transfer
rsync -ahm --info=progress2 --partial ${ws1_path}/ ${ws2_path}

# And again, for good measure
rsync -ahm --info=progress2 --partial ${ws1_path}/ ${ws2_path}

# Exit with the exit code of the rsync
exit $?
