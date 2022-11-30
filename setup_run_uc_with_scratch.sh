#!/bin/bash
set -e

if [[ "$#" -eq "0" ]]; then
	echo "usage:"
	echo "  `basename $0` <maininsfile> "other_ins_files" <grid> <input_module> <np> <imac|keam|linux|scc>"
	exit
fi

module_gnu="$HOME/scripts_peter/module_gnu.sh"

# Get default LPJ-GUESS code location
if [[ "${LPJG_TOPDIR}" == "" ]]; then
    echo "Environment variable LPJG_TOPDIR is blank; will rely on --lpjg_topdir argument." >&2
elif [[ ! -d "${LPJG_TOPDIR}" ]]; then
    echo "LPJG_TOPDIR not found: ${LPJG_TOPDIR}" >&2
    echo "Will rely on --lpjg_topdir argument." >&2
else
    lpjg_topdir="${LPJG_TOPDIR}"
fi

#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="setup_run_uc_with_scratch.sh"
#Declare the number of mandatory args
margs=7

# Common functions - BEGIN
function example {
echo -e "example: $script -s fhlr2 -g GFDL-ESM4 -p \"picontrol historical\" -t 10 -b 5M -x"
}

function usage {
echo " "
echo -e "usage: $script INSFILE \"INSFILE2 ...\" GRIDLIST MODULE NPROC ARCH WALLTIME [-d JOBNUM --dev]\n"
}

function help {
usage
echo -e "OPTIONAL:"
echo -e "  -d --dependency JOBNUM  Start this job after completion of Slurm job JOBNUM\n"
echo -e "  --lpjg_topdir PATH Path to LPJ-GUESS directory that build folder (i.e., ARCH) should be found in"
echo -e "  -L --linked_restart_dir PATH Path to restart directory (.../state/YEAR) that will be linked in this state_path_absolute"
echo -e "  -p --prefix VAL  Add VAL to beginning of Slurm job names\n"
echo -e "  -s --state_path_absolute VAL Absolute path to state directory, if path in ins-files can't be trusted\n"
echo -e "  -r --reservation VAL Job reservation name\n"
echo -e "  --tasks-per-core VAL Tasks per core, [1] or 2\n"
echo -e "  --fu Start finishup job. Default when --dev is not specified. To disable, do --no-fu\n"
echo -e "  --no_fu Do not start finishup job\n"
echo -e "  --dev 						  Use one of the dev queues. Add --fu to also start a finishup job.\n"
echo -e "  --submit					  Go ahead and submit the job (and postprocessing, if applicable).\n"
echo -e "  --append-test-to-parent-instead   When using --dev, append _test to the PARENT of the work directory instead of the work directory itself.\n"
echo -e "  -h,  --help				 Prints this help\n"
example
}

# Ensures that the number of passed args are at least equals
# to the declared number of mandatory args.
# It also handles the special case of the -h or --help arg.
function margs_precheck {
if [ $2 ] && [ $1 -lt $margs ]; then
	if [ $2 == "--help" ] || [ $2 == "-h" ]; then
		help
		exit
	else
		usage
		example
		exit 1 # error
	fi
fi
}

# Ensures that all the mandatory args are not empty
function margs_check {
if [ $# -lt $margs ]; then
	usage
	example
	exit 1 # error
fi
}
# Common functions - END

# Main
margs_precheck $# $1

# SSR: Process positional arguments
insfile=$1
shift
extra_insfiles=$1
shift
gridlist=$1
shift
input_module=$1
shift
nprocess=$1
shift
arch=$1
shift
walltime=$1
shift

# Set default values for non-positional arguments
dependency=
prefix=
state_path_absolute=
dev=0
do_finishup=1
arg_yes_fu=
arg_no_fu=
submit=0
reservation=
linked_restart_dir_array=()
pp_y1=
pp_yN=
tasks_per_core=1
append_test_to_parent_instead=0
# Handle possible neither/both specs here
mem_per_node_default=90000 # MB
mem_per_node=-1 # MB
mem_per_cpu_default=500 # MB
mem_per_cpu=-1 # MB


# Args while-loop
while [ "$1" != "" ];
do
	case $1 in
		-d  | --dependency)  shift
			dependency_tmp=$1
			;;
		--lpjg_topdir )  shift
			lpjg_topdir=$1
			;;
		-L  | --linked_restart_dir)  shift
			linked_restart_dir_array+=($1)
			;;
		-p  | --prefix)  shift
			prefix=$1
			;;
		-s  | --state_path_absolute)  shift
			state_path_absolute=$1
			;;
		-r  | --reservation )  shift
			reservation=$1
			;;
		--tasks-per-core)  shift
			tasks_per_core=$1
			;;
        --mem-per-node)  shift
            mem_per_node=$1
            ;;
        --mem-per-cpu)  shift
            mem_per_cpu=$1
            ;;
		--pp_y1)  shift
			pp_y1=$1
			;;
		--pp_yN)  shift
			pp_yN=$1
			;;
		--dev)  dev=1
			;;
		--fu)  arg_yes_fu=1
			;;
		--no_fu)  arg_no_fu=1
			;;
		--submit)  submit=1
			;;
		--append-test-to-parent-instead | --append_test_to_parent_instead)  append_test_to_parent_instead=1
			;;
		-h	| --help )		  help
			exit
			;;
		*)
			echo "$script: illegal option $1"
			usage
			example
			exit 1 # error
			;;
	esac
	shift
done

# Pass here your mandatory args for check
margs_check $insfile "$extra_insfiles" $gridlist $input_module $nprocess $arch $walltime

# Process memory specification
. "${HOME}/scripts/process_slurm_mem_spec.sh"

# Parse dependency
if [[ "${dependency_tmp}" == "LATEST" ]]; then
	dependency_tmp=$(awk 'END {print $NF}' ${HOME}/submitted_jobs.log)
	echo "Using latest submitted job (${dependency_tmp}) as dependency"
	dependency="#SBATCH -d afterany:$dependency_tmp"
elif [[ "${dependency_tmp}" != "" ]]; then
	echo "Depending on job ${dependency_tmp}"
	dependency="#SBATCH -d afterany:$dependency_tmp"
fi

if [[ "${tasks_per_core}" -eq 1 ]]; then
    bindto_mapby="core"
elif [[ "${tasks_per_core}" -eq 2 ]]; then
    bindto_mapby="hwthread"
else
    echo "tasks_per_core must be 1 or 2; you said: ${tasks_per_core}"
    exit 1
fi

# Do finishup or no?
if [[ ${arg_no_fu} == "1" && ${arg_yes_fu} == "1" ]]; then
	if [[ ${dev} -eq 1 ]]; then
		echo "Both --fu and --no_fu specified. Using dev default of NO finishup."
		do_finishup=0
	else
		echo "Both --fu and --no_fu specified. Using non-dev default of YES finishup."
		do_finishup=1
	fi
elif [[ ${arg_no_fu} == "1" ]]; then
	do_finishup=0
elif [[ ${dev} -eq 1 ]]; then
	if [[ ${arg_yes_fu} == "1" ]]; then
		do_finishup=1
	else
		do_finishup=0
	fi
fi

# Parse absolute state path, if not provided
if [[ "${state_path_absolute}" == "" ]]; then
	topdir=$(realpath ..)
    topdir_work="$(echo $topdir | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@" | sed "s@/$topdir@@")"
    mkdir -p "${topdir_work}"
	state_path_absolute="${topdir_work}/states"
fi

# Get directories, modifying paths if testing
runid=$(basename $PWD)
jobname=${runid}_$(date "+%Y%m%d%H%M%S")
if [[ ${prefix} != "" ]]; then
	jobname=${prefix}_${jobname}
fi
workdir=$WORK
if [[ "${workdir}" == "" ]]; then
	echo "\$WORK undefined"
	exit 1
elif [[ ! -e "${workdir}" ]]; then
	echo "\$WORK not found: $WORK"
	exit 1
fi
rundir_top=$workdir/$(pwd | sed "s@/pfs/data5/home@/home@" | sed "s@${HOME}/@@")
if [[ ${dev} -eq 1 ]]; then
    if [[ ${append_test_to_parent_instead} -eq 1 ]]; then
        thisbasename=$(basename $(realpath "$PWD"/..))
    else
        thisbasename=$(basename "$PWD")
    fi
	rundir_top=$(echo ${rundir_top} | sed "s@${thisbasename}@${thisbasename}_test@")
	state_path_absolute=${state_path_absolute}_test
	if [[ "${linked_restart_dir_array}" != "" ]]; then
		for i in "${!linked_restart_dir_array[@]}"; do 
			lrd=${linked_restart_dir_array[$i]}
			lrd=$(echo ${lrd} | sed "s@${thisbasename}@${thisbasename}_test@")
			linked_restart_dir_array[$i]=${lrd}
		done
	fi
fi

# End function-parsing code
#############################################################################################

# For running on UniCluster
cores_per_node=40 #uc2 nodes, 40 cores with hyperthreading *2. 
tasks_per_node=$((cores_per_node*tasks_per_core))
finishup_t_min=60
if [[ ${nprocess} -gt ${tasks_per_node} ]]; then
	if [[ $((nprocess%tasks_per_node)) != 0 ]]; then
		echo "Please set nprocess to a multiple of ${tasks_per_node}!"
		exit 1
	fi
	nnodes=$((nprocess/tasks_per_node))
	if [[ ${dev} -eq 1 ]]; then
		queue=dev_multiple
		walltime=30:00
	else
		queue=multiple
	fi
	excl_text="#SBATCH --exclusive"
else
	nnodes=1
	if [[ ${dev} -eq 1 ]]; then
		queue=dev_single
		walltime=30:00
		finishup_nprocs=2
	else
		queue=single
	fi
	excl_text=""
fi

# Get info for job_finish, assuming that reservation is only on one queue
if [[ ${reservation} == "" ]]; then
	finishup_partition="single"
	finishup_nprocs=8
	if [[ ${dev} -eq 1 ]]; then
		finishup_t_min=30
		finishup_partition="dev_single"
	fi
else
	finishup_partition=${queue}
fi
if [[ ${finishup_partition} == "multiple" ]]; then
	finishup_nprocs=$((tasks_per_node + 1))
fi

if [[ "${lpjg_topdir}" == "" ]]; then
    echo "You must specify --lpjg_topdir" >&2
    echo "You could also do the following: export LPJG_TOPDIR=/path/to/lpj-guess/code" >&2
    echo "either in this terminal or in ~/.bash_profile" >&2
    exit 1
elif [[ ! -d "${lpjg_topdir}" ]]; then
    echo "lpjg_topdir not found: ${lpjg_topdir}" >&2
    exit 1
fi

echo "queue: ${queue}"
echo "nprocess: ${nprocess}"
echo "nnodes: ${nnodes}"
echo "walltime: ${walltime}"
echo "finishup_partition: ${finishup_partition}"
echo "finishup_nprocs: ${finishup_nprocs}"

lpjg_dir=${lpjg_topdir}/build_$arch
scripts_dir=$HOME/scripts
binary=guess
########################################################################

gridlist_filename=$(basename $gridlist)

#============================================================== ... split to nodes======================

USER=$(whoami)

# ============================================================ prepare work dir ... ===================

mkdir -p "${rundir_top}"
echo "rundir_top = ${rundir_top}"

#======Copy ins, gridlist and executable

rsync -a  $lpjg_dir/$binary $rundir_top

if [[ -e $lpjg_dir/latest_commit.txt ]]; then
	rsync -a  $lpjg_dir/latest_commit.txt $rundir_top
fi
if [[ -e $lpjg_dir/latest_cmake.txt ]]; then
	rsync -a  $lpjg_dir/latest_cmake.txt $rundir_top
fi

cp $gridlist $rundir_top
for ins in $insfile $extra_insfiles; do
	cp $ins $rundir_top
done

if [[ -e postproc.sh ]]; then
	cp postproc.sh $rundir_top/
fi

cd $rundir_top

# Clear existing run* directories
remove_existing_run_directories.sh

# Create and fill run* directories
echo "Creating and filling run*/ directories..."
include_list="--include=${insfile}"
for f in ${extra_insfiles}; do
	include_list="${include_list} --include=$f"
done
include_list="${include_list} --exclude=*"
for ((b=1; b <= $nprocess ; b++)); do

  let "c=((1-1)*$nprocess+$b)"

  # Copy ins-files and info on latest commit associated with guess binary
  if [[ $b -eq 1 ]]; then
	  run1_dir=run$c
	  mkdir $run1_dir
	  rsync -a ${include_list} * ${run1_dir}/
  else
	  cp -r ${run1_dir} run$c
  fi
  if [[ -e latest_commit.txt ]]; then
	  cp latest_commit.txt run$c
  fi
  if [[ -e latest_cmake.txt ]]; then
	  cp latest_cmake.txt run$c
  fi

done
echo " "

# Set up state directory
state_path_relative=$(get_param.sh "${insfile}" state_path | sed 's@%Y@@' | sed "s@//@/@g")
[[ "${state_path_relative}" == "get_param.sh_FAILED" ]] && exit 1
if [[ "${state_path_relative}" != "" ]]; then
#	mkdir -p run1/${state_path_relative}
	echo "state_path_relative: ${state_path_relative}"
	echo "state_path_absolute: ${state_path_absolute}"
	mkdir -p "${state_path_absolute}"
	if [[ "${linked_restart_dir_array}" != "" ]]; then
		pushd "${state_path_absolute}" 1>/dev/null

		for linked_restart_dir in ${linked_restart_dir_array[@]}; do
			# Warn if linked directory doesn't exist. This isn't necessarily a problem---this job
			# might depend on an earlier job that will generate the state directory to be linked.
			if [[ ! -d "${linked_restart_dir}" ]]; then
				echo "Warning: linked_restart_dir $linked_restart_dir does not exist. Linking anyway."
			else
				echo "linked_restart_dir: ${linked_restart_dir}"
			fi
	
			# Remove existing link, if necessary.
			lrd_basename=$(basename "${linked_restart_dir}")
			if [[ -L $lrd_basename ]]; then
				rm -f $lrd_basename
	
			# Remove existing directory, if necessary. Require manual approval if not empty!
			elif [[ -d $lrd_basename ]]; then
				if [[ $(ls $lrd_basename | wc -l) -eq 0 ]]; then
					rmdir $lrd_basename
				else
					echo " "
					echo "WARNING:"
					printf "${state_path_absolute}/${lrd_basename} already exists."
					REPLY=x
					#while [[ "$REPLY" !=~ ^[Yy]$ && "$REPLY" !=~ ^[Nn]$ ]]; do
					#while [[ "$REPLY" =~ ^[^YyNn]$ ]]; do
					while [[ $REPLY =~ ^[^YyNn]$ ]]; do
						printf "\n"
						read -p "Are you sure you want to delete it? Y/N: " -n 1 -r
	#				  echo	 # (optional) move to a new line
					done
					printf "\n"
					if [[ $REPLY =~ ^[Yy]$ ]]; then
						echo "Deleting."
						rm -rf $lrd_basename
					else
						echo "Exiting."
						exit 1
					fi
					echo " "
				fi
			fi
	
			# Make the link
			ln -s "${linked_restart_dir}"
		done
		popd 1>/dev/null
	fi
	echo " "
else
	# No state path found; fill with value that mpi_run_guess_on_tmp.sh will interpret as dummy
	state_path_relative=xyz
	state_path_absolute=xyz
fi

# Split gridlist up into files for each process; distribute to run*/ directories
split_gridlist.sh ${gridlist} ${nprocess}

# Set up reservation
if [[ ${reservation} == "" ]]; then
	reservation_txt_sbatch=""
	reservation_txt=""
	reservation_txt_fu=""
else
	reservation_txt_sbatch="#SBATCH --reservation=${reservation}"
	reservation_txt="--reservation=${reservation}"
	reservation_txt_fu="-r ${reservation}"
fi


#############################################
# Create script that will start the MPI run #
#############################################

cat<<EOL > submit.sh 
#!/bin/bash
#SBATCH --partition $queue
#SBATCH -N $nnodes
#SBATCH -n $nprocess
#SBATCH --ntasks-per-core ${tasks_per_core}
#SBATCH --ntasks-per-node ${tasks_per_node}
#SBATCH ${mem_spec}
#SBATCH -t $walltime
#SBATCH -J $jobname
#SBATCH --output guess_x.o%j
#SBATCH --error guess_x.e%j
${excl_text}
${dependency}
${reservation_txt_sbatch}

set -e

EOL

# 2022-05-05 18:09 PDT: Previously, I had these written directly (uncommented) into submit.sh. But now I'm noticing that they don't match what is in my module_gnu.sh, so I'm replacing them with that script directly. BUT! I haven't tested this with an actual netCDF-forced run! So if it stops working, change it back.
###module unload \$(module -t list 2>&1 | grep "tools\|app\|io\|compiler\|mpi\|lib\|math\|devel\|numlib\|cae\|chem\|system")
###module load compiler/gnu mpi/openmpi
###module list
cat "${module_gnu}" >> submit.sh 

cat<<EOL >> submit.sh
export HDF5_DISABLE_VERSION_CHECK=1

if [[ $(which mpirun | grep "openmpi" | wc -l) -eq 1 ]]; then
    mpirun_options="--bind-to core --map-by core"
else
    mpirun_options=""
fi
diagnostics=1
if [[ \$diagnostics -eq 1 ]]; then
    if [[ \$(which mpirun | grep "openmpi" | wc -l) -eq 1 ]]; then
        #mpirun_options="-display-map -tag-output"
        mpirun_options="${mpirun_options} -report-bindings -display-map -tag-output"
    elif [[ \$(which mpirun | grep "intel" | wc -l) -eq 1 ]]; then
        mpirun_options="${mpirun_options} -print-rank-map -prepend-rank"
    else
        echo "mpirun \$(which mpirun) not recognized; will set no options for stdout/stderr printing"
    fi
fi

# Trying to avoid these warnings:
# common_ucx.c:162  Warning: UCX is unable to handle VM_UNMAP event. This may cause performance degradation or data corruption. Pls try adding --mca opal_common_ucx_opal_mem_hooks 1 to mpirun/oshrun command line to resolve this issue.
mpirun_options+=" --mca opal_common_ucx_opal_mem_hooks 1"

cd $rundir_top 
date +%F\ %H:%M:%S > $rundir_top/RUN_INPROGRESS
echo \$(date) \$PWD job $SLURM_JOBID started >> ~/lpj-model-runs.txt
mpirun \$mpirun_options -n $nprocess ${scripts_dir}/mpi_run_guess_on_tmp.sh $rundir_top/$binary "${state_path_relative}" "${state_path_absolute}" -parallel -input $input_module ${insfile}
LASTERR=\$?
rm $rundir_top/RUN_INPROGRESS
[[ \$LASTERR != 0 ]] && date +%F\ %H:%M:%S > $rundir_top/RUN_FAILED

exit 0

EOL
chmod +x submit.sh


##########################################################
# Create script that will submit jobs and postprocessing #
##########################################################

cat<<EOL > startguess.sh
#!/bin/bash
set -e

jobID=\$(sbatch --mail-type=ALL submit.sh /| sed 's/[^0-9]//g');
if [[ "\${jobID}" == "" ]]; then
	exit 1
fi
echo "LPJ-GUESS run: \$jobID"
date > latest_submitted_jobs.log
echo $PWD >> latest_submitted_jobs.log
echo "LPJ-GUESS run: \$jobID" >> latest_submitted_jobs.log

EOL
if [[ ${do_finishup} -eq 1 ]]; then
	cat<<EOL >> startguess.sh
jobID_finish=\$(job_finish.sh -a ${finishup_partition} -d afterany:\$jobID -t ${finishup_t_min} -p ${finishup_nprocs} -N ${jobname} ${reservation_txt_fu})
if [[ "\${jobID_finish}" == "" ]]; then
	exit 1
fi
echo "job_finish.sh: \$jobID_finish"
echo "job_finish.sh: \$jobID_finish" >> latest_submitted_jobs.log
echo " " >> ${HOME}/submitted_jobs.log
EOL
fi
cat<<EOL >> startguess.sh
cat latest_submitted_jobs.log >> ${HOME}/submitted_jobs.log
cat latest_submitted_jobs.log >> submitted_jobs.log
exit 0
EOL
chmod +x startguess.sh


####################################################
# Either submit or print instructions for doing so #
####################################################

if [[ ${submit} -eq 1 ]]; then
	echo "Submitting..."
    date
	pushd "${rundir_top}" 1>/dev/null 2>&1
	source "${module_gnu}" 1>/dev/null 2>&1
	./startguess.sh
	popd 1>/dev/null 2>&1
else
	echo "To submit:"
	echo "cd $rundir_top"
	echo "source ${module_gnu} 1>/dev/null 2>&1"
	echo "./startguess.sh"
	
	if [[ ${dev} -eq 1 ]]; then
		echo " "
		echo "To submit interactively:"
		echo "cd $rundir_top"
		echo "source ${module_gnu} 1>/dev/null 2>&1"
		echo "salloc --partition $queue -N $nnodes -n $nprocess --ntasks-per-core ${tasks_per_core} -t $walltime ${reservation_txt} submit.sh" 
	fi
fi


exit 0
