#!/bin/bash
set -e

PATH=$PATH:~/software/guess_utilities_1.3/bin

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
dirForPLUM="DIRFORPLUM"
cd "${thisDir}"

pp_y1=OUTY1
while [[ ${pp_y1} -lt OUTYN ]]; do
	pp_yN=$((pp_y1 + NYEARS_POT - 1))

	outDir_thisSSPpd=postproc/THISSSP_${pp_y1}-${pp_yN}
	mkdir -p ${outDir_thisSSPpd}
	echo "   tslicing ${pp_y1}-${pp_yN} tot_runoff..."
	tslice tot_runoff.out -o ${outDir_thisSSPpd}/tot_runoff.out -f ${pp_y1} -t ${pp_yN} -tab -fast
	echo "   gzipping..."
	gzip ${outDir_thisSSPpd}/tot_runoff.out
	touch ${outDir_thisSSPpd}/done

	rsync -ahm ${outDir_thisSSPpd} ${dirForPLUM}/

	# Save run info to directory for PLUM
	tarfile=${dirForPLUM}/THISSSP_${pp_y1}-${pp_yN}/runinfo_act.tar
	tar -cf ${tarfile} *ins
	tar -rf ${tarfile} *txt
	tar -rf ${tarfile} *log

	pp_y1=$((pp_yN + 1))
done

