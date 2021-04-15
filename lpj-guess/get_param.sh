#!/bin/bash
set -e

# Name of this ins-file
insfile=$1
if [[ ! -e "${insfile}" ]]; then
   >&2 echo "get_param.sh: ${insfile} not found!"
   exit 1
elif [[ "${insfile}" == "" ]]; then
   >&2 echo "get_param.sh: You must provide a top insfile"
   exit 1
fi

# Change to the directory
cd $(dirname ${insfile})
insfile=$(basename "${insfile}")

# Name of this parameter
thisparam="$2"
if [[ "${thisparam}" == "" ]]; then
   >&2 echo "get_param.sh: You must provide a parameter name"
   exit 1
fi

function parse_paramstr {
	echo $1 | grep -oE "str\s*\".*\"" | sed "s/str //" | sed 's/"//g'
}

function parse_other {
	echo $1 | sed -E "s/\s*${thisparam}\s+//"
}

# Find all lines beginning (after any spaces) with any of these:
#    thisparam VALUE
#    param "thisparam"
#    import "somefile.ins"
# IFS business makes it so that the elements of the array are distinguished by newlines rather than spaces
IFS_backup=$IFS
IFS=$'\n'
set +e
results=($(grep -E "^\s*${thisparam}\s+|^\s*param\s+\"${thisparam}\"|import" ${insfile}))
set -e
IFS=$IFS_backup

thevalue=""
if [[ "${results}" != "" ]]; then
for (( idx=${#results[@]}-1 ; idx>=0 ; idx-- )) ; do
    thisline="${results[idx]}"


    if [[ $(echo $thisline | awk '{print $1;}') == "import" ]]; then
		 # Check to see if it's defined in this imported ins-file or its dependencies
       importedfile=$(echo $thisline | sed -E "s/\s*import\s*//" | sed -E "s/\!.*//" | sed -E "s/\s+$//" | sed 's/"//g')
       if [[ ! -f ${importedfile} ]]; then
          >&2 echo "get_param.sh: Error: ${insfile} appears to import ${importedfile}, but that doesn't exist"
			 echo "get_param.sh_FAILED"
          exit 1
       fi
		 get_param.sh "${importedfile}" "${thisparam}" > /dev/null
       thevalue=$(get_param.sh "${importedfile}" "${thisparam}")
    else
		 # Remove any comments
		 thevalue=$(echo $thisline | sed -E "s/\s*\!.*//")
       # Remove everything else
		 if [[ $(echo $thevalue | grep -E "^\s*param" | wc -l) -eq 1 ]]; then
			 thevalue=$(parse_paramstr "${thevalue}")
		 else
			 thevalue=$(parse_other "${thevalue}")
		 fi
		 # Remove any quotation marks
		 thevalue=$(echo $thevalue | sed 's/"//g')
    fi

    if [[ "${thevalue}" != "" ]]; then
       echo ${thevalue}
       break
    fi
done
fi

exit 0
