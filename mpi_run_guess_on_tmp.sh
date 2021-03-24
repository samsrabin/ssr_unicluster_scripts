#!/bin/bash
set -e
set -x

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

# Get path to guess binary
guess_binary=$1
shift
if [[ ! -e ${guess_binary} ]]; then
	echo "guess binary ${guess_binary} not found; aborting."
	exit 1
fi

# Get paths to states directory
state_path_relative=$1
shift
state_path_absolute=$1
shift

# The rest of this script's arguments will be used as arguments for call of guess
guess_options=$*

# Get the main ins-file
main_insfile=$(echo ${guess_options} | awk 'NF>1{print $NF}')

# Get rank of this process
unset local_nrank
#for uc2 if run with module mpi/impi mpirun
if [[ -z $local_nrank && ! -z $PMI_RANK ]]; then
	#[163] PMI_RANK=163
	#[163] MPI_LOCALNRANKS=80
	#[163] MPI_LOCALRANKID=3
	local_nrank=$PMI_RANK
fi
if [[ -z $local_nrank && ! -z $OMPI_COMM_WORLD_RANK ]]; then
	local_nrank=$OMPI_COMM_WORLD_RANK
fi
if [[ -z $local_nrank && ! -z $SLURM_PROCID ]]; then
	local_nrank=$SLURM_PROCID
fi
if [[ -z $local_nrank ]]; then
	echo "ERROR: can not determine MPI RANK"
	exit -1
fi
echo "local_nrank $local_nrank"

# Get directories (we use the RANK+1 within LPJ-guess_binary)
local_nrun=$((local_nrank+1))
scratch_work_dir=${TMP}/scratch_${local_nrun}
work_dir=${SLURM_SUBMIT_DIR}
scratch_run_dir=${scratch_work_dir}/run${local_nrun}
work_run_dir=${work_dir}/run${local_nrun}
echo work_dir $work_dir
echo scratch_work_dir $scratch_work_dir
echo work_run_dir ${work_run_dir}
echo scratch_run_dir ${scratch_run_dir}

# Set up subdirectory for this process specifically
mkdir -p ${scratch_run_dir}
if [[ ! -e ${scratch_run_dir} ]]; then
	echo ERROR could not find scratch_run_dir ${scratch_run_dir}
	exit 1
fi

# rsync state, if necessary
scratch_state_dir="$(realpath ${scratch_run_dir}/${state_path_relative})"
do_restart=$(get_param.sh ${main_insfile} restart)
[[ "${do_restart}" == "get_param.sh_FAILED" ]] && exit 1
try_transfer_all=0
if [[ ${do_restart} == "1" ]]; then
	if [[ "${state_path_absolute}" == xyz ]]; then
		echo "When restarting, you must provide state_path_absolute"
		exit 1
	elif [[ ! -e ${state_path_absolute} ]]; then
		echo "state_path_absolute not found: ${state_path_absolute}"
		exit 1
	fi
	# Note that this means state_path in ins-files must be "state/%Y/"
	restart_year=$(get_param.sh ${main_insfile} restart_year)
	[[ "${restart_year}" == "get_param.sh_FAILED" ]] && exit 1
	restart_dir=${state_path_absolute}/${restart_year}
	echo "Transferring state from work to scratch..."
	if [[ ${restart_year} == "" || ! -d "${restart_dir}" ]]; then
		if [[ ${restart_year} == "" ]]; then
			echo "Couldn't parse restart_year"
			exit 1
		else
			echo "parsed restart_dir not found: ${restart_dir}"
			exit 1
		fi
		try_transfer_all=1
	else
		set +e
		rsync -avzL --partial --include="meta.bin" --include="${local_nrank}.state" --include="${restart_year}/" --exclude="**" ${state_path_absolute}/ ${scratch_state_dir}/
		set -e
		rsync -azL --partial --include="meta.bin" --include="${local_nrank}.state" --include="${restart_year}/" --exclude="**" ${state_path_absolute}/ ${scratch_state_dir}/
	fi
elif [[ ${do_restart} != "0" ]]; then
	try_transfer_all=1
fi
if [[ ${try_transfer_all} -eq 1 ]]; then
	echo "Couldn't parse whether this run is restarting. Will try transferring any and all state dirs"
	set +e
	rsync -avzL --partial --include="meta.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${state_path_absolute}/ ${scratch_state_dir}/
	set -e
	rsync -azL --partial --include="meta.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${state_path_absolute}/ ${scratch_state_dir}/
fi

# rsync (twice to be sure!!) work runfiles (ins etc) to scratch rundir
echo "rsyncing working directory to scratch..."
set +e
rsync -az --partial --exclude="state" ${work_run_dir}/ ${scratch_run_dir}/
set -e
rsync -az --partial --exclude="state" ${work_run_dir}/ ${scratch_run_dir}/

# cd into the top-level scratch_work_dir ("guess -parallel" later changes into the actual runNN directory)
cd ${scratch_work_dir}

# Run guess; wait for completion before continuing
echo cmd: ${guess_binary} ${guess_options}
${guess_binary} ${guess_options}
wait

# rsync (twice to be sure!!) things back to the work_dir
echo "rsyncing scratch directory to work..."
set +e
rsync -avz --partial --inplace --exclude="state/" ${scratch_run_dir}/ ${work_run_dir}/
set -e
rsync -az --partial --inplace --exclude="state/" ${scratch_run_dir}/ ${work_run_dir}/

# rsync state, if necessary
do_savestate=$(get_param.sh ${scratch_run_dir}/${main_insfile} save_state)
[[ "${do_savestate}" == "get_param.sh_FAILED" ]] && exit 1
if [[ ${do_savestate} -eq 1 && "${state_path_absolute}" != xyz && -e ${state_path_absolute} ]]; then
	set +e
	echo "Transferring state from scratch to work..."
	rsync -avzK --partial --inplace --include="meta.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${scratch_state_dir}/ ${state_path_absolute}/
	set -e
	rsync -azK --partial --inplace --include="meta.bin" --include="${local_nrank}.state" --include="*/" --exclude="**" ${scratch_state_dir}/ ${state_path_absolute}/
fi

echo ${HOSTNAME} ls ${work_run_dir}
ls ${work_run_dir}

exit 0
