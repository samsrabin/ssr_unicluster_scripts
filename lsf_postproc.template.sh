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

pp_y1=OUTY1
pp_yN=$((pp_y1 + NYEARS_POT - 1))

outDir_thisSSPpd=postproc/THISSSP_${pp_y1}-${pp_yN}
mkdir -p ${outDir_thisSSPpd}
for f in $(ls landsymm_p[cl]ut[CW]*); do
    echo "   gzipping ${f}..."
    gzip < "${f}" > "${outDir_thisSSPpd}/${f}.gz"
done
touch ${outDir_thisSSPpd}/done

rsync -ahm ${outDir_thisSSPpd} ${dirForPLUM}/

# Save run info to directory for PLUM
tarfile=${dirForPLUM}/THISSSP_${pp_y1}-${pp_yN}/runinfo_pot.tar
tar -cf ${tarfile} *ins
tar -rf ${tarfile} *txt
tar -rf ${tarfile} *log

exit 0
