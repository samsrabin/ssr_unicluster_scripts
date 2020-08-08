#!/bin/bash
set -e

# Name of this ins-file
insfile=$1
if [[ ! -e "${insfile}" ]]; then
	echo "${insfile} not found!"
	exit 1
elif [[ "${insfile}" == "" ]]; then
	echo "You must provide an insfile to get_state_dir.sh"
	exit 1
fi
#echo "Importing ${insfile}" >&2

# Import any ins-files this ins-file imports
# Recursive!
for f in $(grep -he "^\s*import" ${insfile} | sed "s/import\s*//" | grep -oe '".*"' | sed 's/"//g'); do
	state_path_tmp="$(get_state_dir.sh $f)"
	if [[ "${state_path_tmp}" != "" ]]; then
		state_path="${state_path_tmp}"
		#		echo $f $state_path >&2
	fi
done

state_path_thisfile=$(grep -E "^\s*state_path" ${insfile} | grep -oE '"\S+"' | sed 's/"//g' | tail -n 1)
if [[ "${state_path_thisfile}" != "" ]]; then
	state_path="${state_path_thisfile}"
	#	echo ${insfile} $state_path >&2
fi

echo $state_path

exit 0
