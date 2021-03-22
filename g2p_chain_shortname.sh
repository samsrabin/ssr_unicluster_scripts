#!/bin/bash

d="${1}"
if [[ "${d}" == "" ]]; then
	>&2 echo g2p_chain_shortname.sh: You must provide a directory name
	exit 1
fi

cli=$(echo $d | cut -d'_' -f2)
soc=$(echo $d | cut -d'_' -f3)
co2=$(echo $d | cut -d'_' -f4)
thischain_name="g2p_${d:0:2}_${cli:0:1}${soc:0:1}${co2:0:1}"

echo "${thischain_name}"

exit 0
