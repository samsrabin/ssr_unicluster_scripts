#!/bin/bash
set -e

timemin=600

N_jobname=""
dependency=""
nprocs=8
reservation=""
if [[ "$CLUSTER" == fh1 || "$SLURM_CLUSTER_NAME" == fh1 ]]; then
	part="singlenode"
elif [[ "$CLUSTER" == uc2 || "$SLURM_CLUSTER_NAME" == uc2 ]]; then
	part="single"
else
	part=""
fi
while getopts ":d:N:p:a:r:t:" opt; do
    case $opt in
        d) dependency="-d ${OPTARG}" ;;
        N) N_jobname="-J jobfin_${OPTARG}" ;;
        p) nprocs=$OPTARG ;;
	  	  a) part=$OPTARG ;;
	  	  r) reservation="--reservation $OPTARG" ;;
        t) timemin=$OPTARG ;;
        :) echo "Missing argument for option -${OPTARG}"; exit 1;;
       \?) echo "Unknown option -${OPTARG}"; exit 1;;
    esac
done
if [[ "${part}" == "" ]]; then
	echo "partition not specified"
	exit 1
fi

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
   mkdir -p "${homedir}"
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
   sbatch --partition ${part} -n ${nprocs} -t ${timemin} ${dependency} -o ${outfile} $N_jobname ${reservation} --mail-type=ALL --export=outfile ~/scripts/finishup_scc.sh $homedir
elif [[ "$CLUSTER" == uc2 || "$SLURM_CLUSTER_NAME" == uc2 ]]; then
   sbatch --partition ${part} -n ${nprocs} -t ${timemin} ${dependency} -o ${outfile} $N_jobname ${reservation} --ntasks-per-core=1 --mem=20000mb --mail-type=ALL --export=outfile ~/scripts/finishup_scc.sh $homedir
else
   echo "ERROR: This cluster not recognized!"
   echo "   CLUSTER:            $CLUSTER"
   echo "   SLURM_CLUSTER_NAME: $SLURM_CLUSTER_NAME"
   exit 1
fi

exit
