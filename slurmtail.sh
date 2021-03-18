#!/bin/bash
set -e

jobid=$1
if [[ "${jobid}" == "" ]]; then
	echo "You must provide a job ID"
	exit 1
fi

jobinfo=$(scontrol show job $jobid)
file_out=$(echo $jobinfo | grep -oE "StdOut=\S+" | sed "s/StdOut=//g")
file_err=$(echo $jobinfo | grep -oE "StdErr=\S+" | sed "s/StdErr=//g")

if [[ "${file_out}" == "${file_err}" ]]; then
	tail -F -n 100 "${file_out}"
else
	multitail -s 2 --follow-all --retry-all -n 100 -i "${file_out}" -i "${file_err}"
fi

exit 0
