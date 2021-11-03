#!/bin/bash
set -e

PATH=$PATH:~/software/guess_utilities_1.3/bin

echo $PWD > this_directory.txt

outDir_thisSSPpd=postproc/THISSSP_OUTY1-OUTYN
mkdir -p ${outDir_thisSSPpd}
echo "   tslicing anpp..."
tslice anpp.out -o ${outDir_thisSSPpd}/anpp.out -f OUTY1 -t OUTYN -tab -fast
echo "   tslicing gsirrigation..."
tslice gsirrigation_st.out -o ${outDir_thisSSPpd}/gsirrigation.out -f OUTY1 -t OUTYN -tab -fast
echo "   tslicing yield..."
tslice yield_st.out -o ${outDir_thisSSPpd}/yield.out -f OUTY1 -t OUTYN -tab -fast
echo "   tslicing gsirrigation_plantyear..."
tslice gsirrigation_plantyear_st.out -o ${outDir_thisSSPpd}/gsirrigation_plantyear.out -f OUTY1 -t OUTYN -tab -fast
echo "   tslicing yield_plantyear..."
tslice yield_plantyear_st.out -o ${outDir_thisSSPpd}/yield_plantyear.out -f OUTY1 -t OUTYN -tab -fast
echo "   gzipping..."
gzip ${outDir_thisSSPpd}/anpp.out
gzip ${outDir_thisSSPpd}/gsirrigation.out
gzip ${outDir_thisSSPpd}/yield.out
gzip ${outDir_thisSSPpd}/gsirrigation_plantyear.out
gzip ${outDir_thisSSPpd}/yield_plantyear.out

# Save run outputs to directory for PLUM
thisDir="${PWD}"
while [[ ! -d outputs/ ]]; do
	cd ../
	if [[ "$PWD" == "/" ]]; then
		echo "Could not find an outputs directory in this directory tree"
		exit 1
	fi
done
cd outputs/
rsync -ahm "${thisDir}/${outDir_thisSSPpd}" DIRFORPLUM/
cd "${thisDir}"

# Save run info to directory for PLUM
tarfile=DIRFORPLUM/THISSSP_OUTY1-OUTYN/runinfo_pot.tar
tar -cf ${tarfile} *ins
tar -rf ${tarfile} *txt
tar -rf ${tarfile} *log

#touch ${outDir_thisSSPpd}/done
####declare -a CFTs=("CerealsC3" "CerealsC4" "Rice" "Oilcrops" "Pulses" "StarchyRoots")
#declare -a CFTs=("CROPLIST")
####declare -a Nferts=("0" "0200" "1000")
#declare -a Nferts=("NFERTLIST")
#declare -a onetwo=("1" "2")
#declare -a irrigs=("" "i")
#
## Get relevant years
#y1=$(basename postproc/*/ | cut -d"-" -f1)
#y5=$(basename postproc/*/ | cut -d"-" -f2)
#
## Boolean harvest or no?
#for x in "${onetwo[@]}"; do
#   did_unzip=0
#   if [[ ! -e hdate${x}.out.extr ]]; then
#      if [[ ! -e hdate${x}.out ]]; then
#         did_unzip=1
#         gunzip < hdate${x}.out.gz > hdate${x}.out
#      fi
#      extract_txt="Year>=${y1}"
#      extract hdate${x}.out -x $extract_txt -o HDATE${x}.out.extr
#   fi
#   compute_txt=""
#   for c in "${CFTs[@]}"; do
#      for i in "${irrigs[@]}"; do
#         for n in "${Nferts[@]}"; do
#            compute_txt="$compute_txt ${c}${i}${n}_h${x}=${c}${i}${n}>0"
#         done
#      done
#   done
#   compute HDATE${x}.out.extr -i Lat Lon Year $compute_txt -n -o HDATE${x}.out.extr.compute
#   if [[ $did_unzip -eq 1 ]]; then
#      rm hdate${x}.out
#   fi
#done
#
## Combine HDATE1 and HDATE2 booleans
#### https://stackoverflow.com/questions/13446255/how-to-remove-the-first-two-columns-in-a-file-using-shell-awk-sed-whatever
#### https://stackoverflow.com/questions/17095306/how-to-add-a-column-from-a-file-to-another-file
#awk '{$1=""; $2=""; $3=""; sub("  ", " "); print}' HDATE2.out.extr.compute > HDATE2.out.extr.compute.tmp
#paste HDATE1.out.extr.compute HDATE2.out.extr.compute.tmp > HDATEs.out.extr.compute.join
#
## Get # harvests over the period (uses custom tslice with -sum option)
#compute_txt=""
#for c in "${CFTs[@]}"; do
#   for i in "${irrigs[@]}"; do
#      for n in "${Nferts[@]}"; do
#         compute_txt="$compute_txt ${c}${i}${n}_nh=${c}${i}${n}_h1+${c}${i}${n}_h2"
#      done
#   done
#done
#compute HDATEs.out.extr.compute.join -i Lat Lon Year $compute_txt -n -o HDATEs.out.extr.compute.join.compute
#tslice HDATEs.out.extr.compute.join.compute -sum -o HDATEs.out.extr.compute.join.compute.tslice
#
## Combine with yield
#if [[ ! -e yield.${y1}-${y5}.out ]]; then
#   gunzip < postproc/${y1}-${y5}/yield.out.gz > yield.${y1}-${y5}.out.tmp
#   compute_txt=""
#   for c in "${CFTs[@]}"; do
#      for i in "${irrigs[@]}"; do
#         for n in "${Nferts[@]}"; do
#            compute_txt="$compute_txt ${c}${i}${n}_y=${c}${i}${n}"
#         done
#      done
#   done
#   compute yield.${y1}-${y5}.out.tmp -i Lat Lon $compute_txt -n -o yield.${y1}-${y5}.out
#fi
#awk '{$1=""; $2=""; sub("  ", " "); print}' HDATEs.out.extr.compute.join.compute.tslice > HDATEs.out.extr.compute.join.compute.tslice.tmp
#paste yield.${y1}-${y5}.out HDATEs.out.extr.compute.join.compute.tslice.tmp > HDATEs.out.extr.compute.join.compute.tslice.tmpPlusYield
#
## Get per-HARVEST average
##compute_txt="'CerealsC3wi1000ph=CerealsC3wi1000*5/CerealsC3wi1000_nh'"
#compute_txt=""
#for c in "${CFTs[@]}"; do
#   for i in "${irrigs[@]}"; do
#      for n in "${Nferts[@]}"; do
#         compute_txt="$compute_txt ${c}${i}${n}=${c}${i}${n}_y*5/${c}${i}${n}_nh"
#      done
#   done
#done
#compute HDATEs.out.extr.compute.join.compute.tslice.tmpPlusYield -i Lat Lon $compute_txt -n -p 3 -o yieldPH.out.tmp
#sed "s/-nan/   0/g" yieldPH.out.tmp > yieldPH.out
#gzip < yieldPH.out > postproc/${y1}-${y5}/yieldPH.out.gz
#
#rm HDATE* yield.${y1}-${y5}.out yieldPH.out yield*.out.tmp
