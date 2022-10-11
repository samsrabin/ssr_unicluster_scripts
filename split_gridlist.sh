#!/bin/bash
set -e

gridlist="$1"
nprocess="$2"

re='^[0-9]+$'
if [[ "${gridlist}" == "" || "${nprocess}" == "" ]]; then
    echo "split_gridlist.sh: You must provide gridlist and nprocess."
    exit 1
elif [[ ! -f "${gridlist}" ]]; then
    echo "split_gridlist.sh: gridlist file not found: ${gridlist}"
    exit 1
elif ! [[ ${nprocess} =~ $re ]] ; then
   echo "split_gridlist.sh: nprocess must be an integer, not ${nprocess}" >&2
   exit 1
fi

gridlist_filename=$(basename "${gridlist}")

# Split gridlist up into files for each process
lines_per_run=$(wc -l ${gridlist} | awk '{ x = $1/'$nprocess'; d = (x == int(x)) ? x : int(x)+1; print d}')
split -a 4 -l $lines_per_run ${gridlist} tmpSPLITGRID_
files=$(ls tmpSPLITGRID_*)
Nfiles=$(echo $files | wc -w)

# Sometimes you can get fewer files than there are processes
if [[ ${Nfiles} -ne ${nprocess} ]]; then
    # Only falling back to this in order to preserve previous behavior when
    # this problem doesn't arise
    rm tmpSPLITGRID_*
    split -a 4 -n r/$nprocess ${gridlist} tmpSPLITGRID_
    files=$(ls tmpSPLITGRID_*)
fi

# Distribute the gridlist files
i=1
for file in $files; do
    let "c=((1-1)*$nprocess+$i)"
    mv $file run$c/${gridlist}_filename
    i=$((i+1))
done

exit 0
