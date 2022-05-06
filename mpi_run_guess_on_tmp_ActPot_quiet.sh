#!/bin/bash
#synchronize the output generate by a mpi job back to the submit run dir
echo "$(date) BEGINNING mpi_run_guess_on_tmp_ActPot_quiet.sh" #>> /home/fh1-project-lpjgpi/lr8247/PLUM/trunk_runs/LPJGPLUM_2001-2100_remap6p6_forPotYields_rcp26/test.out
if [[ $# -eq 0 ]]; then
  echo "usage: $(basename $0) abs.guess options...  "
  exit
fi
#args: abs.guess absolute path to the guess executable
#      options e.g. -input cf -parallel scc_guess.ins
# will use the local $TMP to store the guess output and sync back to the submit dir runNN directory
#if not provided will use the MPI MOAB SLURM info
#will be called with a mpirun mpi_run_guess_on_tmp.sh SUBMIT_DIR/guess -input cf -parallel scc_guess.ins

#prevent /scratch on fh1 and set o slurm job tmpdir
if [[ ${TMP} == "/scratch" ]]; then
 #e.g. /scratch/slurm_tmpdir/job_359622/
 TMP=/scratch/slurm_tmpdir/job_${SLURM_JOBID}
fi

#set -x
thisThisDir=$1
shift
#WORK_DIR=$(echo ${SLURM_SUBMIT_DIR}/${thisThisDir} | sed "s@/pfs/data1/home/kit/imk-ifu@/pfs/work3/fh1-project-lpjgpi@")
#WORK_DIR=$(echo ${SLURM_SUBMIT_DIR}/${thisThisDir} | sed "s@/home/fh1-project-lpjgpi@/pfs/work3/fh1-project-lpjgpi@")
WORK_DIR=$(echo ${SLURM_SUBMIT_DIR}/${thisThisDir} | sed "s@/pfs/data3/project/fh1-project-lpjgpi@/work/fh1-project-lpjgpi@")

# Deal with weird duplication of this directory name in $WORK_DIR
test=$(echo $WORK_DIR | rev | cut -d '/' -f 1 | rev)
if [[ "${test}" == "$(echo $WORK_DIR | rev | cut -d '/' -f 2 | rev)" ]]; then
  WORK_DIR2=$(echo $WORK_DIR | sed "s@$test/$test@$test@")
#  echo Changing WORK_DIR from
#  echo "   $WORK_DIR"
#  echo to
#  echo "   $WORK_DIR2"
  WORK_DIR=$WORK_DIR2
fi

# Get state years
state1_yr=$(basename $WORK_DIR | sed "s/1.2.act.//" | sed "s/1.2.pot.//" | cut -d- -f1)
state1_yr=$((state1_yr-1))
state2_yr=$(basename $WORK_DIR | sed "s/1.2.act.//" | sed "s/1.2.pot.//" | cut -d- -f2)

GUESS=${WORK_DIR}/guess

if [[ -e ${GUESS} ]]; then
echo "$(date) entering [[ -e ${GUESS} ]]" #>> /home/fh1-project-lpjgpi/lr8247/PLUM/trunk_runs/LPJGPLUM_2001-2100_remap6p6_forPotYields_rcp26/test.out
     OPTIONS=$*
   
     # we use the RANK+1 within LPJ-GUESS
     LOCAL_NRUN=$((OMPI_COMM_WORLD_RANK+1))

     # Set up directories
     SCRATCH_WORK_DIR=${TMP}/scratch_${LOCAL_NRUN}
     SCRATCH_RUN_DIR=${SCRATCH_WORK_DIR}/run${LOCAL_NRUN}
     WORK_RUN_DIR=${WORK_DIR}/run${LOCAL_NRUN}
     mkdir -p ${SCRATCH_RUN_DIR}
   
     # Remove existing .out files from this run's work directory
     #if [[ $(ls ${WORK_RUN_DIR}/*.out >/dev/null 2>&1) -eq 0 ]]; then
     if [[ $(ls ${WORK_RUN_DIR}/*.out 2>/dev/null | wc -l) -gt 0 ]]; then
       rm ${WORK_RUN_DIR}/*.out
     fi
   
     if [[ -e ${WORK_DIR}/state ]]; then
         mkdir -p ${SCRATCH_WORK_DIR}/state
         #state1_dir=$(ls -d state/* | head -n 1)
         state1_dir=state/${state1_yr}
         state1=$((LOCAL_NRUN-1)).state
         echo rsyncing ${WORK_DIR}/${state1_dir}/${state1}
         rsync -avz --partial --include="meta.bin" --include="${state1}" --exclude="**" ${WORK_DIR}/${state1_dir}/ ${SCRATCH_WORK_DIR}/${state1_dir}/
         rsync -avz --partial --include="meta.bin" --include="${state1}" --exclude="**" ${WORK_DIR}/${state1_dir}/ ${SCRATCH_WORK_DIR}/${state1_dir}/
         if [[ ! -e ${WORK_DIR}/${state1_dir}/${state1} ]]; then
            echo Initial state file not found!
            exit 1
         fi
         if [[ ! -e ${SCRATCH_WORK_DIR}/${state1_dir}/${state1} ]]; then
            echo Initial state file not rsynced!
            exit 1
         fi
     fi
   
     echo "$(date) rsyncing to SCRATCH_RUN_DIR" #>> /home/fh1-project-lpjgpi/lr8247/PLUM/trunk_runs/LPJGPLUM_2001-2100_remap6p6_forPotYields_rcp26/test.out
     if [[ -e ${SCRATCH_RUN_DIR} ]]; then
        #rsync (twice to be sure!!) work runfiles (ins etc) to scratch rundir
        echo rsyncing ${WORK_RUN_DIR} to ${SCRATCH_RUN_DIR}
        rsync -aqz --partial ${WORK_RUN_DIR}/ ${SCRATCH_RUN_DIR}/
        rsync -aqz --partial ${WORK_RUN_DIR}/ ${SCRATCH_RUN_DIR}/
    
        #only cd into the SCRATCH_WORK_DIR, guess -parallel makes a chdir into the runNN
        cd ${SCRATCH_WORK_DIR}
        ${GUESS} ${OPTIONS}
#        echo "$(date) submitting mpirun" #>> /home/fh1-project-lpjgpi/lr8247/PLUM/trunk_runs/LPJGPLUM_2001-2100_remap6p6_forPotYields_rcp26/test.out
#        mpirun --bind-to core --map-by socket -report-bindings ${GUESS} ${OPTIONS}
    
        wait
    
        #todo: do a md5 on the output and check after the rsync??? could take awhile!!!
        #rsync (twice to be sure!!) things back to the WORK_DIR
        echo rsyncing ${SCRATCH_RUN_DIR} to ${WORK_RUN_DIR}
        rsync -aqz --partial ${SCRATCH_RUN_DIR}/ ${WORK_RUN_DIR}/
        rsync -aqz --partial ${SCRATCH_RUN_DIR}/ ${WORK_RUN_DIR}/
    
        if [[ -e ${WORK_DIR}/state ]]; then
           #state2_dir=$(ls -d state/* | tail -n 1)
           state2_dir=state/${state2_yr}
           state2=$((LOCAL_NRUN-1)).state
           echo rsyncing ${SCRATCH_WORK_DIR}/${state2_dir}/${state2}
           rsync -avz --partial --include="meta.bin" --include="${state2}" --exclude="**" ${SCRATCH_WORK_DIR}/${state2_dir}/ ${WORK_DIR}/${state2_dir}/
           rsync -avz --partial --include="meta.bin" --include="${state2}" --exclude="**" ${SCRATCH_WORK_DIR}/${state2_dir}/ ${WORK_DIR}/${state2_dir}/
        fi
   
     else
        echo ERROR could not find SCRATCH_RUN_DIR ${SCRATCH_RUN_DIR}
        exit 1
     fi
else
  echo ${GUESS} not found!
  exit 1
fi

exit 0
