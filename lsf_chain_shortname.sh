#!/bin/bash

d="${1}"
if [[ "${d}" == "" ]]; then
	>&2 echo lsf_chain_shortname.sh: You must provide a directory name
	exit 1
fi


prefix="lsf"
if [[ "${2}" == 1 ]]; then
	prefix="${prefix}T"
fi

cli=$(echo $d | cut -d'_' -f2)
soc=$(echo $d | cut -d'_' -f3)
if [[ "${soc}" == "hist2015soc" ]]; then
    soc="h2"
fi
co2=$(echo $d | cut -d'_' -f4)
thischain_name="${prefix}_${d:0:2}_${cli:0:1}${soc:0:2}${co2:0:1}"

echo "${thischain_name}"

exit 0
