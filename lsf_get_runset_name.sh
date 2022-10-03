#!/bin/bash

if [[ $PWD == *calibration* ]]; then
    runsetname="calibration"
else
    runsetname=$(lsf_get_basename.sh)
fi

if [[ "${runsetname}" == "" ]]; then
    >&2 echo "lsf_get_runset_name.sh: runsetname is blank"
    exit 1
fi

echo $runsetname

exit 0
