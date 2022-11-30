#!/bin/bash

jobnum="$1"
if [[ "${jobnum}" == "" ]]; then
    echo "You must provide jobnum" >&2
    exit 1
fi

sacct -j "${jobnum}" -o "jobid,jobname,partition,elapsed"

exit 0
