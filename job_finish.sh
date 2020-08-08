#!/bin/bash
set -e

timemin=720

N_jobname=""
dependency=""
nprocs=8
while getopts ":d:N:p:t:" opt; do
    case $opt in
        d) dependency="-d ${OPTARG}" ;;
        N) N_jobname="-J jobfin_${OPTARG}" ;;
        p) nprocs=$OPTARG ;;
        t) timemin=$OPTARG ;;
        :) echo "Missing argument for option -${OPTARG}"; exit 1;;
       \?) echo "Unknown option -${OPTARG}"; exit 1;;
    esac
done

# Get working directory
runid=$(basename $PWD)
jobname=${runid}_$(date "+%Y%m%d%H%M%S")
workdir=$WORK
if [[ "${workdir}" == "" ]]; then
   echo "\$WORK undefined"
   exit 1
elif [[ ! -e "${workdir}" ]]; then
   echo "\$WORK not found: $WORK"
   exit 1
fi
rundir_top=$(pwd | sed "s@${HOME}/@${WORK}@")
homedir=$(pwd | sed "s@${WORK}@${HOME}@")
if [[ ! -e ${homedir} ]]; then
   echo "homedir ${homedir} does not exist"
   exit 1
fi

# Define log and error files
export outfile=$PWD/job_finish.log
export errfile=$PWD/job_finish.err
if [[ -e $outfile ]]; then
   rm $outfile
fi
if [[ -e $errfile ]]; then
   rm $errfile
fi

export LANG=en_US.UTF-8
export WORK=$WORK
if [[ "$CLUSTER" == fh1 || "$SLURM_CLUSTER_NAME" == fh1 ]]; then
   echo ${dependency}
   sbatch --partition singlenode -n ${nprocs} -t ${timemin} ${dependency} -o ${outfile} $N_jobname --mail-type=ALL --export=outfile ~/scripts/finishup_scc.sh $homedir
elif [[ "$CLUSTER" == uc2 || "$SLURM_CLUSTER_NAME" == uc2 ]]; then
   echo ${dependency}
   sbatch --partition single -n ${nprocs} --mem-per-cpu=4000 -t ${timemin} ${dependency} -o ${outfile} $N_jobname --mail-type=ALL --export=outfile ~/scripts/finishup_scc.sh $homedir
else
   echo "ERROR: This cluster not recognized!"
   echo "   CLUSTER:            $CLUSTER"
   echo "   SLURM_CLUSTER_NAME: $SLURM_CLUSTER_NAME"
   exit 1
fi

exit
