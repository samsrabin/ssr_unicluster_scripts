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
dirForPLUM=${PWD}/$(ls -d outForPLUM-* | tail -n 1)
cd "${thisDir}"

pp_y1_array=( QQQQ )
pp_yN_array=( RRRR )
for i in "${!pp_y1_array[@]}"; do
	pp_y1=${pp_y1_array[i]}
	pp_yN=${pp_yN_array[i]}

	mkdir -p postproc/${pp_y1}-${pp_yN}
	echo "   tslicing ${pp_y1}-${pp_yN} tot_runoff..."
	tslice tot_runoff.out -o postproc/${pp_y1}-${pp_yN}/tot_runoff.out -f ${pp_y1} -t ${pp_yN} -tab -fast
	echo "   gzipping..."
	gzip postproc/${pp_y1}-${pp_yN}/tot_runoff.out
	touch postproc/${pp_y1}-${pp_yN}/done

	rsync -ahm postproc/${pp_y1}-${pp_yN} ${dirForPLUM}/

	# Save run info to directory for PLUM
	tarfile=${dirForPLUM}/${pp_y1}-${pp_yN}/runinfo_act.tar
	tar -cf ${tarfile} *ins
	tar -rf ${tarfile} *txt
	tar -rf ${tarfile} *log
done

