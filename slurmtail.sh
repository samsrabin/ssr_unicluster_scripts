#!/bin/bash
set -e

# Output the last ${initn} lines
initn=100

jobid=$1
if [[ "${jobid}" == "" ]]; then
	echo "You must provide a job ID"
	exit 1
fi

options="$@"

jobinfo=$({ scontrol show job $jobid 2>/dev/null || true; })
if [[ "${jobinfo}" == "" ]]; then
	workdir=$(sacct -j $jobid -o WorkDir%1000 | grep -v "WorkDir\|\-\-\-" | grep -E "\S+" | sed -E "s@^\s+/@/@" | sed -E "s@ \$@@")
	if [[ ! -e "${workdir}" ]]; then
		echo "workdir not found: $workdir"
		exit 1
	fi
	file_out="${workdir}/guess_x.o$jobid"
	if [[ ! -e "${file_out}" ]]; then
		echo "file_out not found: $file_out"
		exit 1
	fi
	file_err="${workdir}/guess_x.e$jobid"
	if [[ ! -e "${file_err}" ]]; then
		file_err="${file_out}"
	fi
else
	file_out=$(echo $jobinfo | grep -oE "StdOut=\S+" | sed "s/StdOut=//g")
	file_err=$(echo $jobinfo | grep -oE "StdErr=\S+" | sed "s/StdErr=//g")
fi

echo "file_out: ${file_out}"
if [[ "${file_out}" == "${file_err}" ]]; then
	multitail -s 2 --follow-all --retry-all -n ${initn} ${options} -i "${file_out}"
else
	echo "file_err: ${file_err}"
	multitail -s 2 --follow-all --retry-all -n ${initn} ${options} -i "${file_out}" -i "${file_err}"
fi

exit 0
