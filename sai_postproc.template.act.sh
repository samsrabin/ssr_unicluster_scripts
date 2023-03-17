#!/bin/bash
set -e

PATH=$PATH:~/software/guess_utilities_1.3/bin

echo $PWD > this_directory.txt

dirForPLUM=DIRFORPLUM

pp_y1_array=( QQQQ )
pp_yN_array=( RRRR )
for i in "${!pp_y1_array[@]}"; do
	pp_y1=${pp_y1_array[i]}
	pp_yN=${pp_yN_array[i]}

	thisDir=${pp_y1}-${pp_yN}_THISSSP

	mkdir -p postproc/${thisDir}
	echo "   tslicing ${thisDir} tot_runoff..."
	tslice tot_runoff.out -o postproc/${thisDir}/tot_runoff.out -f ${pp_y1} -t ${pp_yN} -tab -fast
	echo "   gzipping..."
	gzip postproc/${thisDir}/tot_runoff.out
	touch postproc/${thisDir}/done

	rsync -ahm postproc/${thisDir} ${dirForPLUM}/

	# Save run info to directory for PLUM
	tarfile=${dirForPLUM}/${thisDir}/runinfo_act.tar
	tar -cf ${tarfile} *ins
	tar -rf ${tarfile} *txt
	tar -rf ${tarfile} *log
done

