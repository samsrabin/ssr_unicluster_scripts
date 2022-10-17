#!/bin/bash

thisdir="${1}"
if [[ "${thisdir}" == "" ]]; then
    echo "You must provide forPLUM directory" >&2
    exit 1
elif [[ ! -d "${thisdir}" ]]; then
    echo "forPLUM directory not found: ${thisdir}" >&2
    exit 1
fi

cd "${thisdir}"

dirlist="$(ls -d *[0-9])"
processlist=""
skiplist=""
for d in ${dirlist}; do
    filename=$d.tar
    if [[ -e $filename ]]; then
        skiplist+="${d} "
    else
        processlist+="${d} "
    fi
done

echo "Skipping because tar file exists already:"
for d in ${skiplist}; do echo "   $d"; done
echo "Archiving and uploading:"
for d in ${processlist}; do echo "   $d"; done
for d in ${processlist}; do
    filename=$d.tar
    [[ -e $filename ]] && continue
    echo $filename
    tar -cf $filename $d
    rclone copy -P $filename dropbox:"Sharing_remote/$(basename $(dirname $(realpath ..)))"
done

exit 0
