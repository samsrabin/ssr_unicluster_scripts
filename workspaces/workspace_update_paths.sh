#!/bin/bash
set -e

# Get path to old workspace
ws1=$1
if [[ ${ws1} == "" ]]; then
    echo "You must provide old workspace name!"
    exit 1
fi
ws1_path=$(ws_find ${ws1})
if [[ ${ws1_path} == "" ]]; then
    ws1_path="/pfs/work7/workspace/scratch/${USER}-${ws1}-0"
    echo "Workspace ${ws1} not found! Trying ${ws1_path}"
    if [[ -d "${ws1_path}" ]]; then
        "That directory already exists. This is unexpected!"
        exit 1
    fi
fi
ws1=$1

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

# Make sure directory exists
d="$3"
if [[ ${d} == "" ]]; then
    echo "You must provide directory name!"
    exit 1
fi
if [[ ! -d "${d}" ]]; then
    echo "Directory ${d} not found!"
    exit 1
fi

filelist=($({ grep -l "${ws1_path}" $(find "${d}" -type f -and \( \( -name "*ins" -or -name "*sh" \) -not -wholename "*BAD*" -not -wholename "*3b.*" \)) || true; }))
if [[ "${filelist}" == "" ]]; then
    echo "No files in ${d}/ contain path to ${ws1}"
    exit 0
fi
echo "Replacing path to ${ws1} with path to ${ws2}:"
for f in "${filelist[@]}"; do
    echo "    ${f}"
    sed -i "s@${ws1_path}@${ws2_path}@g" "${f}"
done


exit 0
