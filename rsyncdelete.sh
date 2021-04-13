#!/bin/bash
set -e

quick=1
verbose=

if [[ "$@" == "" ]]; then
    echo "You must supply at least one directory to delete"
    exit 1
fi

if [[ $quick -eq 0 ]]; then
    total_size=$(du -shc $@ | tail -n 1)
    echo "${total_size}"
fi

dir_array=($@)
ndir=${#dir_array[@]}

thisdate=$(date "+%Y%m%d%H%S%N")
empty_dir="$HOME/.rsyncdelete_empty_${thisdate}"
mkdir ${empty_dir}

i=0
for dir_to_delete in ${dir_array[@]}; do
    i=$((i + 1))

    if [[ ! -d "${dir_to_delete}" ]]; then
        echo "${dir_to_delete} not found; skipping."
        continue
    else
        if [[ $quick -eq 1 ]]; then
            echo "Deleting ${i}/${ndir}: $dir_to_delete"
        else
            echo "Deleting ${i}/${ndir}: $(du -sh $dir_to_delete)"
        fi
        rsync -a${verbose} --delete ${empty_dir}/ ${dir_to_delete}/
        rmdir ${dir_to_delete}
    fi

done


for d in $(ls -d ~/.rsyncdelete_empty*); do
    rmdir $d
done


exit 0
