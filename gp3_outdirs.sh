#!/usr/bin/env bash
set -e

topdir=/pfs/work7/workspace/scratch/xg4606-work/GGCMI/runs_2022-09/isimip3b
echo ${topdir}/

shortname="${1}"
if [[ "${shortname}" == "" ]]; then
    echo "You must provide GCM shortname." >&2
    exit 1
fi
any="${2}"

cd "${topdir}"

latestsubmitsh=
if [[ "${any}" == "" ]]; then
    latestsubmitsh=$(realpath $(ls -tr $(find "${shortname}"* -name "submit.sh") | tail -n 1))
fi
for d in $(ls -trd ${shortname}*/*/ | grep -v "_test" | grep -v "states"); do
    cd $d
    if [[ "${latestsubmitsh}" != "" ]]; then
        latest_guess_xo="$(find . -name "guess_x.o*" -newer ${latestsubmitsh} | sort | grep -v "/logs" | tail -n 1)"
    else
        latest_guess_xo="$(find . -name "guess_x.o*" | sort | grep -v "/logs" | tail -n 1)"
    fi
    if [[ ${latest_guess_xo} == "" ]]; then
        cd ../../
        continue
    fi
    m=$(stat -c "%y" "${latest_guess_xo}" | sed "s/.000000000//")
    j=$(echo ${latest_guess_xo} | sed "s/guess_x.o//" | sed "s@./@@")
    t=$(sacct -j $j -o "jobid,jobname,partition,elapsed" | grep "gp3" | grep -oE "([0-9]+:?)+" | grep ":")
    echo $t $m $d
    cd ../..
done


exit 0
