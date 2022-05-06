#!/bin/bash
#synchronize the output generate by a mpi job back to the submit run dir
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
#WORK_DIR=$(echo ${SLURM_SUBMIT_DIR}/${thisThisDir} | sed "s@/pfs/data1/home/kit/imk-ifu@/pfs/work3/fh1-project-lpjgpi@")
WORK_DIR=$(echo ${SLURM_SUBMIT_DIR}/${thisThisDir} | sed "s@/pfs/data3/project/fh1-project-lpjgpi@/work/fh1-project-lpjgpi@")

# Dead with weird duplication of this directory name in $WORK_DIR
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

GUESS=${WORK_DIR}/guess
#echo $GUESS
if [[ -e ${GUESS} ]]; then
  OPTIONS=$*

#the defaults

  #we use the RANK+1 within LPJ-GUESS
  LOCAL_NRUN=$((OMPI_COMM_WORLD_RANK+1))
  SCRATCH_WORK_DIR=${TMP}/scratch_${LOCAL_NRUN}
  SCRATCH_RUN_DIR=${SCRATCH_WORK_DIR}/run${LOCAL_NRUN}
  WORK_RUN_DIR=${WORK_DIR}/run${LOCAL_NRUN}

  # Remove existing .out files from this run's work directory
  #if [[ $(ls ${WORK_RUN_DIR}/*.out >/dev/null 2>&1) -eq 0 ]]; then
  if [[ $(ls ${WORK_RUN_DIR}/*.out 2>/dev/null | wc -l) -gt 0 ]]; then
    rm ${WORK_RUN_DIR}/*.out
  fi

  mkdir -p ${SCRATCH_RUN_DIR}

  if [[ -e ${WORK_DIR}/state ]]; then
    mkdir -p ${SCRATCH_WORK_DIR}/state
#    state2_dir=$(ls -d state/* | tail -n 1)
#    state2=$((LOCAL_NRUN-1)).state
#    rsync -az --partial --include="meta.bin" --include="${state2}" --exclude="**" ${WORK_DIR}/${state2_dir}/ ${SCRATCH_WORK_DIR}/${state2_dir}/
#    rsync -aqz --partial --include="meta.bin" --include="${state2}" --exclude="**" ${WORK_DIR}/${state2_dir}/ ${SCRATCH_WORK_DIR}/${state2_dir}/
    state1_dir=state/${state1_yr}
    state1=$((LOCAL_NRUN-1)).state
    FROM=${WORK_DIR}/${state1_dir}/
    TO=${SCRATCH_WORK_DIR}/${state1_dir}/
    echo rsyncing ${FROM}/${state1} to $TO
    if [[ ! -e "${FROM}/${state1}" ]]; then
       echo "${FROM}/${state1} does not exist!"
       exit 1
    fi
    rsync -aqz --partial --include="meta.bin" --include="${state1}" --exclude="**" ${WORK_DIR}/${state1_dir}/ ${SCRATCH_WORK_DIR}/${state1_dir}/
   echo "again" 
    rsync -aqz --partial --include="meta.bin" --include="${state1}" --exclude="**" ${WORK_DIR}/${state1_dir}/ ${SCRATCH_WORK_DIR}/${state1_dir}/
    if [[ ! -e ${WORK_DIR}/${state1_dir}/${state1} ]]; then
       echo Initial state file ${state1} not found!
       exit 1
    fi
    if [[ ! -e ${SCRATCH_WORK_DIR}/${state1_dir}/${state1} ]]; then
       echo Initial state file ${state1} not rsynced!
       exit 1
    fi
  fi

 ###mkdir -p ${SCRATCH_RUN_DIR}

  if [[ -e ${SCRATCH_RUN_DIR} ]]; then
    #rsync (twice to be sure!!) work runfiles (ins etc) to scratch rundir
    echo "rsyncing work ins-files etc..."
    rsync -aqz --partial ${WORK_RUN_DIR}/ ${SCRATCH_RUN_DIR}/
    echo "again..."
    rsync -aqz --partial ${WORK_RUN_DIR}/ ${SCRATCH_RUN_DIR}/

    #only cd into the SCRATCH_WORK_DIR, guess -parallel makes a chdir into the runNN
    cd ${SCRATCH_WORK_DIR}
    echo "Doing guess..."
    ${GUESS} ${OPTIONS}

    wait

    #todo: do a md5 on the output and check after the rsync??? could take awhile!!!
    #rsync (twice to be sure!!) things back to the WORK_DIR
    echo rsyncing output...
    rsync -avz --partial ${SCRATCH_RUN_DIR}/ ${WORK_RUN_DIR}/
    echo again...
    rsync -avz --partial ${SCRATCH_RUN_DIR}/ ${WORK_RUN_DIR}/

###    if [[ -e ${WORK_DIR}/state ]]; then
###      state2_dir=$(ls -d state/* | tail -n 1)
###      state2=$((LOCAL_NRUN-1)).state
###      rsync -aqz --partial --include="meta.bin" --include="${state2}" --exclude="**" ${SCRATCH_WORK_DIR}/${state2_dir}/ ${WORK_DIR}/${state2_dir}/
###      rsync -aqz --partial --include="meta.bin" --include="${state2}" --exclude="**" ${SCRATCH_WORK_DIR}/${state2_dir}/ ${WORK_DIR}/${state2_dir}/
###    fi

  else
    echo ERROR could not find SCRATCH_RUN_DIR ${SCRATCH_RUN_DIR}
    exit 1
  fi
else
  echo ${GUESS} not found!
  exit 1
fi

exit 0
