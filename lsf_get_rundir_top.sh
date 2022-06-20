#!/bin/bash

istest=$1
if [[ "${istest}" == "" ]]; then
    istest=0
elif [[ "${istest}" != "0" && "${istest}" != "1" ]]; then
    >&2 echo "Invalid value for istest. Must be 0 or 1, not ${istest}"
    exit 1
fi

ispot=$2
if [[ "${ispot}" == "" ]]; then
    ispot=0
elif [[ "${ispot}" != "0" && "${ispot}" != "1" ]]; then
    >&2 echo "Invalid value for ispot. Must be 0 or 1, not ${ispot}"
    exit 1
fi

if [[ ${ispot} -eq 1 ]]; then
   while [[ ! -d template ]]; do
       cd ../
       if [[ "$PWD" == "/" ]]; then
           echo "lsf_setup.sh must be called from a (subdirectory of a) directory that has a template/ directory"
           exit 1
       fi
   done
   # cd to equivalent directory on $WORK
   cd "$(get_equiv_workdir.sh "$PWD")"
   # cd to any actual directory
   cd actual
   cd $(ls -d */ | head -n 1)
fi

if [[ "${WORK}" == "" ]]; then
   >&2 echo "\$WORK undefined"
   exit 1
elif [[ ! -e "${WORK}" ]]; then
   >&2 echo "\$WORK not found: $WORK"
   exit 1
fi

# Get name of this runset
runsetname=$(lsf_get_runset_name.sh)
if [[ "${runsetname}" == "" ]]; then
    echo "runsetname is blank"
    exit 1
fi

if [[ ${ispot} -eq 0 ]]; then
    rundir_top="$WORK/$(pwd | sed "s@/pfs/data5/home@/home@" | sed "s@${HOME}/@@")"
else
    rundir_top="${PWD}"
fi
if [[ ${istest} -eq 1 ]]; then
    rundir_top=$(echo ${rundir_top} | sed "s@${runsetname}@${runsetname}_test@")
fi

echo $rundir_top

exit 0
