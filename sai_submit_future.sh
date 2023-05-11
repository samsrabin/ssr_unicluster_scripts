#!/bin/bash
set -e

hist=$1
fut=$2
if [[ "${fut}" == "" ]]; then
    echo "You must provide historical and future ensemble members." >&2
    exit 1
fi

# Left-pad with zeros
printf -v hist "%03d" ${hist}
printf -v fut "%03d" ${fut}

which_runset="remap10.N0_actual_hist2015soc_default"
topdir="SAI-landsymm/runs/${which_runset}"
cd "$HOME/${topdir}"

dirForPLUM="$WORK/${topdir}/hist${hist}/outputs/hist${hist}-fut${fut}"

now=$(date +%Y%m%d%H%M%S)
logfile="runs20230502.h${hist}.f${fut}.${now}.log"

rc_setup.sh sai --ensemble-member-hist ${hist} --ensemble-member-fut ${fut} \
    --ssp-list "ssp245 arise1.5" --dirForPLUM ${dirForPLUM} \
    -s | tee -p "${logfile}"

exit 0
