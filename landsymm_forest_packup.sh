#!/bin/bash
set -e

topdir="$1"
if [[ "${topdir}" == "" ]]; then
    echo "You must provide topdir (.../YYYYpast)"
    exit 1
elif [[ ! -d "${topdir}" ]]; then
    echo "topdir not found: ${topdir}"
    exit 1
fi

cd "${topdir}/.."
topdir="$(basename "${topdir}")"

packdir="${topdir}.forPLUM.$(date "+%Y%m%d%H%M%S")"
mkdir "${packdir}"

cd "${topdir}"

do_test="${2}"
if [[ "${do_test}" != "" ]]; then
    dir_list="[0-9]*_test/"
else
    dir_list=$(ls -d [0-9]*/ | grep -v "test")
fi

for d in ${dir_list}; do
    packdir_this="../${packdir}/${d}"
    mkdir -p "${packdir_this}"
    latest="$(ls -d ${d}output* | tail -n 1)"
    echo $PWD/${latest}
    echo "${latest}" > "${packdir_this}/sourcedir"
    #rsync -ahm --include "*landsymm*gz" --exclude="*" "${latest}"/* "${packdir_this}"
    rsync -ahm --exclude "*plutW_from_[cp]*" --include "*landsymm*gz" --exclude="*" "${latest}"/* "${packdir_this}"
done

cd .. 
tar -cf "${packdir}.tar" "${packdir}"

echo $PWD/${packdir}.tar


exit 0
