#!/bin/bash

if [[ $PWD == *calibration* ]]; then
    runsetname="calibration"
else
    runsetname=$(g2p_get_basename.sh)
fi

if [[ "${runsetname}" == "" ]]; then
    >&2 echo "get_runset_name.sh: runsetname is blank"
    exit 1
fi

echo $runsetname

exit 0
