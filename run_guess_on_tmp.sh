#!/bin/bash
set -e
#set -x

# Set verbosity
#    0: Minimal
#    1: Messages about what the script is doing
#    2: 1, plus verbose rsync output
verbose=1

# Set up verbosity info
rsync_verbosity=""
if [[ $verbose -eq 2 ]]; then
	rsync_verbosity="--verbose"
fi

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

# Get scratch working directory for this job
if [[ ${TMP} == "/scratch" ]]; then
	#e.g. /scratch/slurm_tmpdir/job_359622/
	TMP=/scratch/slurm_tmpdir/job_${SLURM_JOBID}
fi

# Get number of this job in the "manual parallel" setup
runnr=$1
shift

# Get path to guess binary
guess_binary=$1
shift
if [[ ! -e ${guess_binary} ]]; then
	echo "guess binary ${guess_binary} not found; aborting."
	exit 1
fi

# Get paths to states directory
state_path_relative=$1
if [[ "${state_path_relative}" == "" ]]; then
	echo "Error: you must specify state_path_relative as 3rd argument"
	exit 1
fi
#echo state_path_relative $state_path_relative
shift
state_path_absolute=$1
if [[ "${state_path_absolute}" == "" ]]; then
	echo "Error: you must specify state_path_absolute as 4th argument"
	exit 1
fi
#echo state_path_absolute $state_path_absolute
shift

# The rest of this script's arguments will be used as arguments for call of guess
guess_options=$*
#echo guess_options $guess_options

# Get rank of this process
unset local_nrank
local_nrank=$((runnr-1))

# Get directories (we use the RANK+1 within LPJ-guess_binary)
local_nrun=$((local_nrank+1))
scratch_work_dir=${TMP}/scratch_${local_nrun}
work_dir=${PWD}
scratch_run_dir=${scratch_work_dir}/run${local_nrun}
work_run_dir=${work_dir}/run${local_nrun}
#echo work_dir $work_dir
#echo scratch_work_dir $scratch_work_dir
#echo work_run_dir ${work_run_dir}
#echo scratch_run_dir ${scratch_run_dir}

# Set up subdirectory for this process specifically
mkdir -p ${scratch_run_dir}
if [[ ! -e ${scratch_run_dir} ]]; then
	echo ERROR could not find scratch_run_dir ${scratch_run_dir}
	exit 1
fi

if [[ $verbose -gt 0 ]]; then
	echo "run${runnr}: cleaning up scratch directory..."
fi
rm -rf ${scratch_run_dir}/*

# rsync state, if necessary
if [[ "${state_path_absolute}" != xyz && -e ${state_path_absolute} ]]; then
	# Note that this means state_path in ins-files must be "state/%Y/"
	scratch_state_dir="$(realpath ${scratch_run_dir}/${state_path_relative})"
	if [[ $verbose -gt 0 ]]; then
		echo "run${runnr} ($(date)): rsyncing state from work (${state_path_absolute}/) to scratch (${scratch_state_dir}/)..."
	fi
	rsync -azL ${rsync_verbosity} --partial --include="meta.bin" --include="meta${local_nrank}.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${state_path_absolute}/ ${scratch_state_dir}/
	rsync -azL --partial --include="meta.bin" --include="meta${local_nrank}.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${state_path_absolute}/ ${scratch_state_dir}/
fi

# rsync (twice to be sure!!) work runfiles (ins etc) to scratch rundir
if [[ $verbose -gt 0 ]]; then
	echo "run${runnr} ($(date)): rsyncing working directory (${work_run_dir}/) to scratch (${scratch_run_dir}/)..."
fi
rsync -az ${rsync_verbosity} --partial --exclude="state" ${work_run_dir}/ ${scratch_run_dir}/
rsync -az --partial --exclude="state" ${work_run_dir}/ ${scratch_run_dir}/

# cd into the scratch_run_dir (i.e., ${scratch_work_dir}/run$((local_nrank+1)) )
cd ${scratch_run_dir}

# Print information about this process
if [[ $verbose -gt 0 ]]; then
	echo "run${runnr} local_nrank=$local_nrank, SLURMD_NODENAME=$SLURMD_NODENAME, pwd $PWD"
fi

# Run guess; wait for completion before continuing
set +e
if [[ $verbose -gt 0 ]]; then
	echo "run${runnr} cmd ($(date)): ${guess_binary} ${guess_options}"
fi
${guess_binary} ${guess_options}
#valgrind --error-limit=no --track-origins=yes --log-file=${work_run_dir}/valgrind.log ${guess_binary} ${guess_options}
wait

# rsync (twice to be sure!!) things back to the work_dir
if [[ $verbose -gt 0 ]]; then
	echo "run${runnr}: rsyncing scratch directory (${scratch_run_dir}/) to work (${work_run_dir}/)..."
fi
rsync -az ${rsync_verbosity} --partial --exclude="state/" ${scratch_run_dir}/ ${work_run_dir}/
rsync -az --partial --exclude="state/" ${scratch_run_dir}/ ${work_run_dir}/

# rsync state, if necessary
if [[ "${state_path_absolute}" != xyz && -e ${state_path_absolute} ]]; then
	if [[ $verbose -gt 0 ]]; then
		echo "run${runnr}: rsyncing state from scratch (${scratch_state_dir}/) to work (${state_path_absolute}/)..."
	fi
	rsync -azL ${rsync_verbosity} --partial --include="meta.bin" --include="meta${local_nrank}.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${scratch_state_dir}/ ${state_path_absolute}/
	rsync -azL --partial --include="meta.bin" --include="meta${local_nrank}.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${scratch_state_dir}/ ${state_path_absolute}/
fi

if [[ $verbose -gt 0 ]]; then
	echo ${HOSTNAME} ls ${work_run_dir}
	ls ${work_run_dir}
fi

if [[ $verbose -gt 0 ]]; then
	echo "run${runnr}: cleaning up scratch directory..."
fi
rm -rf ${scratch_run_dir}/*

exit 0
