#!/bin/bash
set -e

# Name of this ins-file
insfile=$1
if [[ ! -e "${insfile}" ]]; then
   >&2 echo "get_ins_dependencies.sh: ${insfile} not found!"
   exit 1
elif [[ "${insfile}" == "" ]]; then
   >&2 echo "get_ins_dependencies.sh: You must provide a top insfile"
   exit 1
fi

# Change to the directory
cd $(dirname ${insfile})
insfile=$(basename "${insfile}")

# Find all lines beginning (after any spaces) with:
#    import "somefile.ins"
# IFS business makes it so that the elements of the array are distinguished by newlines rather than spaces
IFS_backup=$IFS
IFS=$'\n'
set +e
results=($(grep -E "^\s*import" ${insfile}))
set -e
IFS=$IFS_backup

if [[ "${results}" != "" ]]; then
for (( idx=${#results[@]}-1 ; idx>=0 ; idx-- )) ; do
    thisline="${results[idx]}"
    f=$(echo $thisline | sed -E 's@^\s*import "(\S+.ins)".*@\1@')
    f_dependencies="$(get_ins_dependencies.sh $f)"
    if [[ "${f_dependencies}" != "" ]]; then
        dependencies="$dependencies $f_dependencies"
    fi
    dependencies="$dependencies $f"
done
fi

echo $dependencies


exit 0
