#!/bin/bash
set -e

if [[ "$#" -eq "0" ]]; then
	echo "usage:"
	echo "  `basename $0` <maininsfile> "other_ins_files" <grid> <input_module> <np> <imac|keam|linux|scc>"
	exit
fi

lpjg_topdir=$HOME/lpj-guess_git-svn_20190828

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
echo -e "usage: $script INSFILE \"INSFILE2 ...\" GRIDLIST MODULE NPROC ARCH walltime [-d JOBNUM --dev]\n"
}

function help {
usage
echo -e "OPTIONAL:"
echo -e "  -d --dependency JOBNUM  Start this job after completion of Slurm job JOBNUM\n"
echo -e "  -p --prefix VAL  Add VAL to beginning of Slurm job names\n"
echo -e "  -s --state_path_absolute VAL Absolute path to state directory, if path in ins-files can't be trusted\n"
echo -e "  -r --reservation VAL Job reservation name\n"
echo -e "  --pp Start postprocessing run. Default when --dev is not specified. To disable, do --no-pp\n"
echo -e "  --no_fu Do not start finishup job\n"
echo -e "  --no_pp Do not start postprocessing job\n"
echo -e "  --dev 						  Use one of the dev queues. Add --pp to also start a postprocessing job.\n"
echo -e "  --submit					  Go ahead and submit the job (and postprocessing, if applicable).\n"
echo -e "  -h,  --help             Prints this help\n"
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
do_postproc=1
arg_yes_fu=
arg_no_fu=
submit=0
reservation=

# Args while-loop
while [ "$1" != "" ];
do
	case $1 in
		-d  | --dependency)  shift
			dependency="#SBATCH -d afterany:$1"
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
		--dev)  dev=1
			;;
		--fu)  arg_yes_fu=1
			;;
		--no_fu)  arg_no_fu=1
			;;
		--no_pp)  do_postproc=0
			;;
		--submit)  submit=1
			;;
		-h   | --help )        help
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

# Do finishup or no?
if [[ ${arg_no_fu} == "1" && ${arg_yes_fu} == "1" ]]; then
	if [[ ${dev} -eq 1 ]]; then
		echo "Both --pp and --no_pp specified. Using dev default of NO postprocessing."
		do_finishup=0
	else
		echo "Both --pp and --no_pp specified. Using non-dev default of YES postprocessing."
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

# End function-parsing code
#############################################################################################

# For running on UniCluster
cores_per_node=40 #uc2 nodes, 40 cores with hyperthreading *2. 
#tasks_per_core=2 # Ends up running out of memory...
tasks_per_core=1
tasks_per_node=$((cores_per_node*tasks_per_core))
finishup_t_min=720
finishup_nprocs=8
finishup_partition="single"
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
if [[ ${dev} -eq 1 ]]; then
	finishup_t_min=30
	finishup_partition="dev_single"
fi 

echo "queue: ${queue}"
echo "nprocess: ${nprocess}"
echo "nnodes: ${nnodes}"
echo "walltime: ${walltime}"

lpjg_dir=${lpjg_topdir}/build_$arch
#scripts_dir=$HOME/scripts
scripts_dir=$HOME/scripts
binary=guess
########################################################################

gridlist_filename=$(basename $gridlist)

#============================================================== ... split to nodes======================

USER=$(whoami)

# Get working directories
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
	rundir_top="${rundir_top}_test"
fi
mkdir -p "${rundir_top}"

# ============================================================ prepare work dir ... ===================

#======Copy ins, gridlist and executable

rsync -a  $lpjg_dir/$binary $rundir_top

# SSR 2017-05-30
if [[ -e $lpjg_dir/latest_commit.txt ]]; then
	rsync -a  $lpjg_dir/latest_commit.txt $rundir_top
fi

cp $gridlist $rundir_top
for ins in $insfile $extra_insfiles; do
	cp $ins $rundir_top
done

# Copy postprocessing script to work
if [[ ${do_postproc} -eq 1 ]]; then
	cp $HOME/scripts/start_isimip3_pp.sh $rundir_top/postproc.sh
	
	if [[ -e ./postproc.sh ]]; then
		cp  ./postproc.sh $rundir_top
	elif [[ -e ../postproc.sh ]]; then
		cp  ../postproc.sh $rundir_top
	elif [[ -e ../../postproc.sh ]]; then
		cp  ../../postproc.sh $rundir_top
	elif [[ -e ~/scripts/postproc.sh ]]; then
		cp  ~/scripts/postproc.sh $rundir_top
	fi
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

done
echo " "

# Set up state directory
state_path_relative=$(get_param.sh "${insfile}" state_path | sed 's@%Y@@' | sed "s@//@/@g")
[[ "${state_path_relative}" == "get_param.sh_FAILED" ]] && exit 1
if [[ "${state_path_relative}" != "" ]]; then
#	mkdir -p run1/${state_path_relative}
	if [[ "${state_path_absolute}" == "" ]]; then
		state_path_absolute="$(realpath "run1/${state_path_relative}")"
	fi
	if [[ ${dev} -eq 1 ]]; then
		state_path_absolute=${state_path_absolute}_test
	fi
	echo "state_path_relative: ${state_path_relative}"
	echo "state_path_absolute: ${state_path_absolute}"
	echo " "
	mkdir -p "${state_path_absolute}"
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
else
	reservation_txt_sbatch="#SBATCH --reservation=${reservation}"
	reservation_txt="--reservation=${reservation}"
fi


####################################################
# Create script that will manually submit each job #
####################################################


## Get number of first run on this node (minus 1, b/c see how $nlocal is calculated)
#nrun=$(($cores_per_node*($a-1)))
#echo node: ${a}, run start: $((nrun+1))

# Write submit.sh
cat<<EOL > submit.sh
#!/bin/bash
#SBATCH --partition $queue
#SBATCH -N $nnodes
#SBATCH -n $nprocess
#SBATCH --ntasks-per-core ${tasks_per_core}
#SBATCH -t $walltime
#SBATCH -J $jobname
#SBATCH --output guess_x.o%j
#SBATCH --error guess_x.e%j
${excl_text}
${dependency}
${reservation_txt_sbatch}

set -e

module unload \$(module -t list 2>&1 | grep "tools\|app\|io\|compiler\|mpi\|lib\|math\|devel\|numlib\|cae\|chem\|system")
module load compiler/gnu mpi/impi
module list
export HDF5_DISABLE_VERSION_CHECK=1

#module load compiler/intel lib/netcdf/4.7.3-intel-19.1 mpi/impi

cd ${rundir_top}
echo \$(date) $LOCAL_DIR job \$slurm_jobid ntasks \$SLURM_NTASKS started >> ~/lpj-model-runs.txt

# Submit each job
set +e
for ((b=1; b <= $nprocess; b++)); do
	#let nlocal="$nrun+\$b"
	nlocal=\$b
	echo "Starting process \${nlocal} ..."
	run_guess_on_tmp.sh \${nlocal} ${rundir_top}/$binary "${state_path_relative}" "${state_path_absolute}" -input $input_module ${insfile} &
done

# Wait until all the started background jobs are done.
wait

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

EOL
if [[ ${do_finishup} -eq 1 ]]; then
	cat<<EOL >> startguess.sh
jobID_finish=\$(job_finish.sh -a ${finishup_partition} -d afterany:\$jobID -t ${finishup_t_min} -p ${finishup_nprocs} -N ${jobname})
if [[ "\${jobID_finish}" == "" ]]; then
	exit 1
fi
echo "job_finish.sh: \$jobID_finish"
EOL
fi
cat<<EOL >> startguess.sh
exit 0
EOL
chmod +x startguess.sh


####################################################
# Either submit or print instructions for doing so #
####################################################

if [[ ${submit} -eq 1 ]]; then
	echo "Submitting..."
   pushd "${rundir_top}" 1>/dev/null 2>&1
   source ~/scripts_peter/module_gnu.sh 1>/dev/null 2>&1
   ./startguess.sh
   popd 1>/dev/null 2>&1
else
	echo "To submit:"
	echo "cd $rundir_top"
	echo "source ~/scripts_peter/module_gnu.sh 1>/dev/null 2>&1"
	echo "./startguess.sh"
	
#	if [[ ${dev} -eq 1 ]]; then
		echo " "
		echo "To submit interactively:"
		echo "cd $rundir_top"
		echo "source ~/scripts_peter/module_gnu.sh 1>/dev/null 2>&1"
		echo "salloc --partition $queue -N $nnodes -n $nprocess --ntasks-per-core ${tasks_per_core} -t $walltime ${reservation_txt} submit.sh" 
#	fi
fi


exit 0
