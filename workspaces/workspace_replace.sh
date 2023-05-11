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

# Make sure new workspace does NOT exist
ws2=${1}
shift
if [[ ${ws2} == "" ]]; then
    echo "You must provide new workspace name!"
    exit 1
fi
if [[ $(ws_list -s | grep "${ws2} ") != "" ]]; then
    echo "Workspace ${ws2} already exists! If you want to transfer ${ws1} to ${ws2}, do:"
    echo "    workspace_transfer.sh ${ws1} ${ws2}"
    exit 1
fi

incl_excl="$@"

ws_allocate ${ws2} 9999999

echo "Transferring ${ws1} to ${ws2}..."

workspace_transfer.sh ${ws1} ${ws2} ${incl_excl}
exitcode=$?

if [[ $exitcode -eq 0 ]]; then
    echo "Completed successfully. To release old workspace:"
    echo "    ws_release ${ws1}"
else
    echo "workspace_transfer.sh exited with code $exitcode"
fi


exit 0
