#!/bin/bash
set -e

topdir=$1
if [[ $topdir == "" ]]; then
   echo "You must provide a directory to work on."
   cat << EOF
usage: gzip_for_ed2.sh DIRECTORYPATTERN [YEAR1 [YEARN]]
   DIRECTORYiPATTERN: The directory pattern you want to use (XX where RCP number should be).
   YEAR1:     The start year of the first included potential run (default 1961).
                (First postprocessed year will be YEAR1+5; first PLUM-output year
                will be YEAR1+10.)
   YEARN:     The end year of the last included potential run (default 2100).
EOF
   exit 1
elif [[ ! -d $topdir ]]; then
   echo "$topdir does not exist."
   exit 1
fi

YEAR1_IN=${2:-1961}
YEARN_IN=${3:-2100}
YEARN_IN=$((YEARN_IN-9))
if [[ $YEAR1_IN -gt $YEARN_IN ]]; then
   echo "YEAR1_IN ($YEAR1_IN) must be <= YEARN_IN ($YEARN_IN)."
   exit 1
fi

cd $topdir
outdir=${topdir}_forED_$(date +'%Y%m%d%H%M%S')
mkdir -p $outdir
touch $outdir/included_directories.txt

skip_runoff=0

echo Copying...
year1=$YEAR1_IN
actual_year1=""
actual_yearN=$YEARN_IN
echo "" > tmp_list_outDirs_act.txt
echo "" > tmp_list_outDirs_pot.txt
while [ $year1 -le $YEARN_IN ]; do
   year6=$((year1 + 5))
   year10=$((year1 + 9))
   thisdir=1.2.pot.$year1-$year10
   if [ "$actual_year1" == "" ]; then
      if [ ! -d "$thisdir" ]; then
         year1=$((year1 + 5))
         continue
      else
         actual_year1=$year1
      fi
   elif [ ! -d "$thisdir" ]; then
      echo "${thisdir} not found; stopping loop."
      actual_yearN=$year1
      break
   fi
   thisout=$(ls -d $thisdir/out* | tail -n 1)
   echo $thisout | sed "s/${thisdir}\///" >> tmp_list_outDirs_pot.txt
   echo $thisout/postproc/$year6-$year10
   cp -r $thisout/postproc/$year6-$year10 $outdir/
   thisdir=1.2.act.$year6-$year10
   thisout=$(ls -d $thisdir/out* | tail -n 1)
   echo $thisout | sed "s/${thisdir}\///" >> tmp_list_outDirs_act.txt
   echo $thisout/postproc/$year6-$year10
   if [[ -e $thisout/postproc/$year6-$year10/tot_runoff.out.gz ]]; then
      cp $thisout/postproc/$year6-$year10/tot_runoff.out.gz $outdir/$year6-$year10
   else
      echo $thisout/postproc/$year6-$year10/tot_runoff.out.gz not found! Skipping tot_runoff.
      skip_runoff=1
   fi
   echo $(pwd)/$thisout >> $outdir/included_directories.txt
   year1=$((year1 + 5))
done

# Check that outputs are chronologically sequential
sort tmp_list_outDirs_pot.txt > tmp_list_outDirs_pot_sorted.txt
if [ $(diff -w -B tmp_list_outDirs_pot.txt tmp_list_outDirs_pot_sorted.txt | wc -l) -gt 0 ]; then
   echo "POTENTIAL outputs not sequential:"
   echo " diff:"
   diff -y tmp_list_outDirs_pot.txt tmp_list_outDirs_pot_sorted.txt | while read -r line; do echo "$line"; done
   while true; do
      read -p "Is that OK? Yy=yes, Nn=no, Dd='no and delete outdir' " yn
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) exit;;
          [Dd]* ) rm tmp*.txt; rm -rf $outdir; rm tmp_list_outDirs_*.txt; exit;;
          * ) echo ${small_file_reprompt};;
      esac
   done
fi
sort tmp_list_outDirs_act.txt > tmp_list_outDirs_act_sorted.txt
if [ $(diff tmp_list_outDirs_act.txt tmp_list_outDirs_act_sorted.txt | wc -l) -gt 0 ]; then
   echo "ACTUAL outputs not sequential:"
   diff -y tmp_list_outDirs_act.txt tmp_list_outDirs_act_sorted.txt | while read -r line; do echo "$line"; done
   while true; do
      read -p "Is that OK? Yy=yes, Nn=no, Dd='no and delete outdir' " yn
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) exit;;
          [Dd]* ) rm tmp*.txt; rm -rf $outdir; rm tmp_list_outDirs_*.txt; exit;;
          * ) echo ${small_file_reprompt};;
      esac
   done
fi

# Check outputs
cd $outdir
year1=$((actual_year1+5))
small_files_ok=0
small_file_prompt="Yy=yes, Nn=no, Aa='yes to this and any subsequent small files', Dd='no and delete outdir'"
small_file_reprompt="Please answer yes, no, all, or delete."
while [ $year1 -le $actual_yearN ]; do
   thisyear_dir=$year1-$((year1+4))
   if [ ! -d $thisyear_dir ]; then
      echo "Error: Directory $thisyear_dir not found in output!"
      exit 1
   fi

   # Check ANPP
   FILENAME=$thisyear_dir/anpp.out.gz
   FILESIZE=$(stat -c%s "$FILENAME")
   if [ "$FILESIZE" -lt 4000000 ] && [ $small_files_ok -eq 0 ]; then
      while true; do
          read -p "Size of ${FILENAME} is only ${FILESIZE}. Is that OK? ${small_file_prompt} " yn
          case $yn in
              [Yy]* ) break;;
              [Nn]* ) exit;;
              [Aa]* ) small_files_ok=1; break;;
              [Dd]* ) rm -rf $outdir; rm ../tmp_list_outDirs_*.txt; exit;;
              * ) echo ${small_file_reprompt};;
          esac
      done
   fi

   # Check gsirrigation
   FILENAME=$thisyear_dir/gsirrigation.out.gz
   FILESIZE=$(stat -c%s "$FILENAME")
   if [ "$FILESIZE" -lt 3500000 ] && [ $small_files_ok -eq 0 ]; then
      while true; do
          read -p "Size of ${FILENAME} is only ${FILESIZE}. Is that OK? ${small_file_prompt} " yn
          case $yn in
              [Yy]* ) break;;
              [Nn]* ) exit;;
              [Aa]* ) small_files_ok=1; break;;
              [Dd]* ) rm -rf $outdir; rm ../tmp_list_outDirs_*.txt; exit;;
              * ) echo ${small_file_reprompt};;
          esac
      done
   fi

   # Check runoff
   if [[ $skip_runoff -eq 0 ]]; then
      FILENAME=$thisyear_dir/tot_runoff.out.gz
      FILESIZE=$(stat -c%s "$FILENAME")
      if [ "$FILESIZE" -lt 700000 ] && [ $small_files_ok -eq 0 ]; then
         while true; do
             read -p "Size of ${FILENAME} is only ${FILESIZE}. Is that OK? ${small_file_prompt} " yn
             case $yn in
                 [Yy]* ) break;;
                 [Nn]* ) exit;;
                 [Aa]* ) small_files_ok=1; break;;
                 [Dd]* ) rm -rf $outdir; rm ../tmp_list_outDirs_*.txt; exit;;
                 * ) echo ${small_file_reprompt};;
             esac
         done
      fi
   fi

   # Check yield
   FILENAME=$thisyear_dir/yield.out.gz
   FILESIZE=$(stat -c%s "$FILENAME")
   if [ "$FILESIZE" -lt 3000000 ] && [ $small_files_ok -eq 0 ]; then
      while true; do
          read -p "Size of ${FILENAME} is only ${FILESIZE}. Is that OK? ${small_file_prompt} " yn
          case $yn in
              [Yy]* ) break;;
              [Nn]* ) exit;;
              [Aa]* ) small_files_ok=1; break;;
              [Dd]* ) rm -rf $outdir; rm ../tmp_list_outDirs_*.txt; exit;;
              * ) echo ${small_file_reprompt};;
          esac
      done
   fi

   # Check yieldPH
   FILENAME=$thisyear_dir/yieldPH.out.gz
   rm $FILENAME
###   FILESIZE=$(stat -c%s "$FILENAME")
###   if [ "$FILESIZE" -lt 3000000 ] && [ $small_files_ok -eq 0 ]; then
###      while true; do
###          read -p "Size of ${FILENAME} is only ${FILESIZE}. Is that OK? ${small_file_prompt} " yn
###          case $yn in
###              [Yy]* ) break;;
###              [Nn]* ) exit;;
###              [Aa]* ) small_files_ok=1; break;;
###              [Dd]* ) rm -rf $outdir; rm ../tmp_list_outDirs_*.txt; exit;;
###              * ) echo ${small_file_reprompt};;
###          esac
###      done
###   fi

   year1=$((year1 + 5))
done
rm ${topdir}/tmp_list_outDirs_*.txt
cd ..

echo gathering into ${outdir}.tar ...
tar -cf ${outdir}.tar $outdir

echo Done!
