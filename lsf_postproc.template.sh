#!/bin/bash
set -e

echo $PWD > this_directory.txt

dirForPLUM="DIRFORPLUM"
cd "${thisDir}"

thisSSP=$(echo $PWD | rev | cut -d"/" -f3 | rev)
thisPot=$(echo $PWD | rev | cut -d"/" -f2 | rev)
lastYear="-$(echo ${thisPot} | cut -d"-" -f2)"
dirName="$(echo ${thisPot} | sed -E "s/_[0-9]+//")"
if [[ "${thisSSP}" != "hist" ]]; then
    dirName+="_${thisSSP}"
fi
outDir_thisSSPpd=postproc/${dirName}
mkdir -p ${outDir_thisSSPpd}
for f in $(ls landsymm_p[cl]ut[CW]*); do
    echo "   gzipping ${f}..."
    gzip < "${f}" > "${outDir_thisSSPpd}/${f}.gz"
done
touch ${outDir_thisSSPpd}/done

rsync -ahm ${outDir_thisSSPpd} ${dirForPLUM}/

# Save run info to directory for PLUM
tarfile=${dirForPLUM}/${dirName}/runinfo_pot.tar
tar -cf ${tarfile} *ins
tar -rf ${tarfile} *txt
tar -rf ${tarfile} *log

exit 0
