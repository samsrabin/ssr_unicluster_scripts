#!/bin/bash
set -e

# Make sure old workspace exists
ws1=$1
shift
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
ws2=${1}
shift
if [[ ${ws2} == "" ]]; then
    echo "You must provide new workspace name!"
    exit 1
fi
ws2_path=$(ws_find ${ws2})
if [[ ${ws2_path} == "" ]]; then
    echo "Workspace ${ws2} not found!"
    exit 1
fi

incl_excl="$@"

# Do the transfer
echo Starting rsync 1
set +e
rsync -ahm --info=progress2 --partial --remove-source-files ${incl_excl} ${ws1_path}/ ${ws2_path}

# And again, for good measure
echo Starting rsync 2
rsync -ahm --info=progress2 --partial --remove-source-files ${incl_excl} ${ws1_path}/ ${ws2_path}
exitcode=$?
set -e

# Exit with the exit code of the rsync
echo Done
exit $exitcode
