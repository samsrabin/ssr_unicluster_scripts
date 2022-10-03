#!/bin/bash
set -e

echo $PWD > this_directory.txt

dirForPLUM="DIRFORPLUM"
cd "${thisDir}"

thisSSP=THISSSP
thisPot=THISPOT
theseYears="THISY1-THISYN"
dirName=${thisPot}_${theseYears}
if [[ "${thisSSP}" != "hist" ]]; then
    dirName+="_${thisSSP}"
fi
outDir_thisSSPpd=postproc/${dirName}
mkdir -p ${outDir_thisSSPpd}
for f in $(ls landsymm_p[cl]ut[CW]*); do
    echo "   gzipping ${f}..."
    gzip < "${f}" > "${outDir_thisSSPpd}/${f}.gz"
done
gzip < cflux_landsymm_sts.out > "${outDir_thisSSPpd}/cflux_landsymm_sts.out.gz"
touch ${outDir_thisSSPpd}/done

rsync -ahm ${outDir_thisSSPpd} ${dirForPLUM}/

# Save run info to directory for PLUM
tarfile=${dirForPLUM}/${dirName}/runinfo_pot.tar
tar -cf ${tarfile} *ins
tar -rf ${tarfile} *txt
tar -rf ${tarfile} *log

exit 0
