#!/bin/bash

istest=$1
if [[ "${istest}" == "" ]]; then
    istest=0
elif [[ "${istest}" != "0" && "${istest}" != "1" ]]; then
    >&2 echo "Invalid value for istest. Must be 0 or 1, not ${istest}"
    exit 1
fi

if [[ "${WORK}" == "" ]]; then
   >&2 echo "\$WORK undefined"
   exit 1
elif [[ ! -e "${WORK}" ]]; then
   >&2 echo "\$WORK not found: $WORK"
   exit 1
fi

# Get name of this runset
runsetname=$(get_runset_name.sh)
if [[ "${runsetname}" == "" ]]; then
    echo "runsetname is blank"
    exit 1
fi

rundir_top="$WORK/$(pwd | sed "s@/pfs/data5/home@/home@" | sed "s@${HOME}/@@")"
if [[ ${istest} -eq 1 ]]; then
    rundir_top=$(echo ${rundir_top} | sed "s@${runsetname}@${runsetname}_test@")
fi

echo $rundir_top

exit 0
