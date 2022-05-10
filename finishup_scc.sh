#!/bin/bash
#SBATCH --output job_finish.%j.log
set -e
#Script for postprocessing of LPJ-GUESS output run on multiple cpus

datenow="$(date)"
echo ${datenow}

LANG=en_US.UTF-8

# save log file
start_msg="Job ${SLURM_JOB_ID} started ${datenow}"
echo "${start_msg}" >> "${WORK_DIR}/latest_submitted_jobs.log"
echo "${start_msg}" >> "${WORK_DIR}/submitted_jobs.log"
echo "${start_msg}" >> "~/submitted_jobs.log"

# Make sure you're okay to do this
if [[ -e RUN_INPROGRESS ]]; then
   echo Canceling because file RUN_INPROGRESS exists.
   exit 255
elif [[ -e RUN_FAILED ]]; then
   echo Canceling because file RUN_FAILED exists.
   exit 255
fi

# Define output directory
outdir=output-`date +%F-%H%M%S`
echo "+++outdir: $outdir"
mkdir $outdir

# Define home directory
homedir=$1
if [[ "${homedir}" == "" ]]; then
   echo "Missing homedir!"
   exit 1
fi

# How many CPUs are available?
if [[ $SLURM_NPROCS != "" ]]; then
   NPROCS=$SLURM_NPROCS
else
   NPROCS=1
fi

# How many runs?
nruns=`find . -regex ".*/run[0-9]+" | wc -l`
echo $PWD "nruns $nruns"

#Run a faster append_files.sh
echo "+++Concatenating *.out files..."
find run1 -name '*.out' | sed 's,run1/,,g' | xargs -n $NPROCS -P $NPROCS ~/scripts/append_files.sh $nruns

# Move files to outdir
echo "+++Moving concatenated *.out files to $outdir ..."
mv *.out $outdir
# Move latest job.log WITH A NUMBER (i.e., not job_finish.log), if it exists
if [[ $(ls job_[0-9]*.log 2> /dev/null | wc -l) -gt 0 ]]; then
   mv $(ls -tr job_[0-9]*.log | tail -n 1) $outdir
fi
# Move latest job.err, if it exists
if [[ $(ls job*.err 2> /dev/null | wc -l) -gt 0 ]]; then
   mv $(ls -tr job*.err | tail -n 1) $outdir
fi
# Move latest job.time, if it exists
if [[ $(ls job*.time 2> /dev/null | wc -l) -gt 0 ]]; then
   mv $(ls -tr job*.time | tail -n 1) $outdir
fi

#also append some logs
echo "+++Concatenating log (and state) files..."
for ((idx=1;idx<=${nruns};idx++)) 
do 
  echo run${idx} guess.log
  echo "+++run${idx}/guess.log" >> $outdir/guess_runs.log
  cat run${idx}/guess.log >> $outdir/guess_runs.log
  if [[ -e run${idx}/state.log ]]; then
      cat run${idx}/state.log >> $outdir/state_runs.log
  fi
done

# Copy setup files and executable into output directory
cp *.ins $outdir/
cp *.txt $outdir/
cp guess $outdir/

# Working in outdir from now on
cd $outdir

# Do postprocessing
echo "+++Postprocessing..."
if [[ -e "postproc.sh" || -e "../postproc.sh"  || -e "../../postproc.sh" ]]; then
   [[ -e "../../postproc.sh" ]] && cp ../../postproc.sh .
   [[ -e "../postproc.sh" ]] && cp ../postproc.sh .
   ./postproc.sh
else
   echo "+++ NONE!!!!"
fi

# List the files that we have put into outdir
echo "+++Concatenation complete. Files in $outdir:"
find .

# Some sanity checks
# IF clauses using awk avoids problem of grep exiting code 1 when no matches found.
echo "+++Performing sanity checks..."
touch skipping.txt
if [[ $(awk 'BEGIN{IGNORECASE=1} /skip/ {print; count++; if (count=1) exit}' guess_runs.log) != "" ]]; then
   grep -B 1 -A 2 -i 'guess.log\|skip' guess_runs.log | grep -v "^$\|Finished\|complete" > skipping.txt
fi
touch warnings.txt
if [[ $(awk 'BEGIN{IGNORECASE=1} /warning/ {print; count++; if (count=1) exit}' guess_runs.log) != "" ]]; then
   grep -B 3 -A 2 -i 'guess.log\|warning' guess_runs.log | grep -v "^$\|Finished\|complete" > warnings.txt
fi
touch errors.txt
if [[ $(awk 'BEGIN{IGNORECASE=1} /error/ {print; count++; if (count=1) exit}' guess_runs.log) != "" ]]; then
   grep -B 3 -A 2 -i 'guess.log\|error' guess_runs.log | grep -v "^$\|Finished\|complete" > errors.txt
fi
touch deserialize.txt
if [[ $(awk 'BEGIN{IGNORECASE=1} /failed to find element to deserialize/ {print; count++; if (count=1) exit}' guess_runs.log) != "" ]]; then
   grep -i 'guess.log\|failed to find element to deserialize' guess_runs.log | grep -v "^$\|Finished\|complete" > deserialize.txt
fi
# If no result returned here then something went really wrong and you should exit anyway.
grep 'guess.log\|Finished' guess_runs.log > runs_finished.txt

#grep -A 10 'guess.log\|Commencing' guess_runs.log | grep -v complete | grep -A 1 -B 5 'guess.log\|Check\|rror\|Warning\|sum not' > lu_error.log

skipped=`grep -i 'skip' guess_runs.log | wc -l`
warned=`grep -i 'warning' guess_runs.log | wc -l`
errors=`grep -i 'errori\|fail' guess_runs.log | wc -l`

successes=`grep 'Finished' guess_runs.log | wc -l`
echo Skipped   ${skipped}
echo Warnings  ${warned}
echo Errors    ${errors}
echo Completed runs: ${successes}/${nruns}

# Get md5sums
echo "+++Getting md5sums for concatenated .out files..."
find . -maxdepth 1 -name '*.out' | xargs -n $NPROCS -P$NPROCS md5sum > md5_out.txt

# Get four lists of files for efficient zipping
echo "" > file_lists
for i in `seq -s' ' 1 $NPROCS`; do
   echo "" > file_list_$i
done
x=0
for i in `ls -S *.out`; do
   if [[ $x -lt $NPROCS ]]; then
      x=$((x + 1))
   else
      x=1
   fi
   echo "$i" >> file_list_$x
done

# Zip up output files
echo "+++gziping..."
for i in `seq -s' ' 1 $NPROCS`; do

	# Save contents of this file list in parent file_lists,
	# since we'll be deleting file_list_* later
	echo file_list_${i} >> file_lists
	echo " "
	cat file_list_${i} >> file_lists
	printf "\n\n\n" >> file_lists

	# Submit gzip job as background process
   gzip -f $(cat file_list_${i}) &
done
wait

# Clean up file lists
rm file_list_*

#gzip -f guess_runs.log

# Get md5sums
echo "+++Getting md5sums for zipped files..."
find . -maxdepth 1 -name '*.gz' | xargs -n $NPROCS -P$NPROCS md5sum > md5_gz.txt

## Copy to $HOME
#cd ..
#mkdir -p $homedir
#echo "+++Copying to $homedir..."
#cp -v -r $outdir $homedir
#
#echo "+++checking gz md5..."
#pushd $homedir/$outdir
#md5sum -c md5_gz.txt > md5_gz_check.txt
#popd

echo `date` `pwd` >> ~/lpj-model-runs.txt
echo   `basename $0` $* into ${homedir}/$outdir >> ~/lpj-model-runs.txt
echo     Skipped   ${skipped} >> ~/lpj-model-runs.txt
echo     Warnings  ${warned} >> ~/lpj-model-runs.txt
echo     Errors    ${errors} >> ~/lpj-model-runs.txt

echo "All done!"
datenow="$(date)"
echo ${datenow}

# save log file
cd ..
end_msg="Job ${SLURM_JOB_ID} ended ${datenow}"
echo "${end_msg}" >> "${WORK_DIR}/latest_submitted_jobs.log"
echo "${end_msg}" >> "${WORK_DIR}/submitted_jobs.log"
echo "${end_msg}" >> "~/submitted_jobs.log"

#cd ..
#cp $OUTFILE $outdir/
#cp $OUTFILE $homedir/$outdir/

exit 0
