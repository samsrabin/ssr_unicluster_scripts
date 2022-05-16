#!/bin/bash
set -e

echo $PWD > this_directory.txt

thisDir="${PWD}"
while [[ ! -d outputs/ ]]; do
   cd ../
   if [[ "$PWD" == "/" ]]; then
      echo "Could not find an outputs directory in this directory tree"
      exit 1
   fi
done
cd outputs/
dirForPLUM=${PWD}/$(ls -d outForPLUM-* | tail -n 1)
cd "${thisDir}"

thisSSP=$(echo $PWD | rev | cut -d"/" -f3 | rev)
thisPot=$(echo $PWD | rev | cut -d"/" -f2 | rev)
lastYear="-$(echo ${thisPot} | cut -d"-" -f2)"
dirName="$(echo ${thisPot} | grep -oE "[0-9]+pot")-${lastYear}"
if [[ "${thisSSP}" != "hist" ]]; then
    dirName+="_${thisSSP}"
fi
dirName+="-$(echo ${thisPot} | cut -d"-" -f2)"
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
