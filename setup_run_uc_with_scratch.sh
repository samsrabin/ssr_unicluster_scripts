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
echo -e "usage: $script INSFILE \"INSFILE2 ...\" GRIDLIST MODULE NPROC ARCH WALLTIME [-d JOBNUM --dev]\n"
}

function help {
usage
echo -e "OPTIONAL:"
echo -e "  -d --dependency JOBNUM  Start this job after completion of Slurm job JOBNUM\n"
echo -e "  -p --prefix VAL  Add VAL to beginning of Slurm job names\n"
echo -e "  --dev 						  Use one of the dev queues\n"
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
dev=0

# Args while-loop
while [ "$1" != "" ];
do
	case $1 in
#		-i  | --insfile)  shift
#			insfile=$1
#			;;
#		-x  | --extra_insfiles )  shift
#			extra_insfiles=$1
#			;;
#		-g  | --gridlist)  shift
#			gridlist=$1
#			;;
#		-m  | --input_module)  shift
#			input_module=$1
#			;;
#		-n  | --nprocess)  shift
#			nprocess=$1
#			;;
#		-a  | --arch)  shift
#			arch=$1
#			;;
		-d  | --dependency)  shift
			dependency="#SBATCH -d afterany:$1"
			;;
		-p  | --prefix)  shift
			prefix=$1
			;;
		--dev)  dev=1
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

# End function-parsing code
#############################################################################################

# For running on UniCluster
cores_per_node=40 #uc2 nodes, 40 cores with hyperthreading *2. 
tasks_per_core=2 # Might not be needed.
tasks_per_node=$((cores_per_node*tasks_per_core))
finishup_t_min=720
finishup_nprocs=8
if [[ ${nprocess} -gt ${tasks_per_node} ]]; then
	if [[ $((nprocess%tasks_per_node)) != 0 ]]; then
		echo "Please set nprocess to a multiple of ${tasks_per_node}!"
		exit 1
	fi
	nnodes=$((nprocess/tasks_per_node))
	if [[ ${dev} == "dev" ]]; then
		queue=dev_multiple
		walltime=30:00
	else
		queue=multiple
	fi
	excl_text="#SBATCH --exclusive"
else
	nnodes=1
	if [[ ${dev} == "dev" ]]; then
		queue=dev_single
		walltime=30:00
		finishup_t_min=30
		finishup_nprocs=2
	else
		queue=single
	fi
	excl_text=""
fi

echo "queue: ${queue}"
echo "nprocess: ${nprocess}"
echo "nnodes: ${nnodes}"
echo "walltime: ${walltime}"
echo ${excl_text}

lpjg_dir=${lpjg_topdir}/build_$arch
#scripts_dir=/pfs/data1/home/kit/imk-ifu/lr8247/scripts
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

# If there's a postproc somewhere, copy it over to work
if [[ -e ./postproc.sh ]]; then
	cp  ./postproc.sh $rundir_top
elif [[ -e ../postproc.sh ]]; then
	cp  ../postproc.sh $rundir_top
elif [[ -e ../../postproc.sh ]]; then
	cp  ../../postproc.sh $rundir_top
elif [[ -e ~/scripts/postproc.sh ]]; then
	cp  ~/scripts/postproc.sh $rundir_top
fi

cd $rundir_top

# Clear existing run* directories
set +e
ls -d run*/ 1> /dev/null 2>&1
result=$?
set -e
if [[ $result == 0 ]]; then
	echo "Removing existing run*/ directories..."
	for d in $(ls -d run*/ | grep -E "^run[0-9]+/"); do
		rm $d/*
		rmdir $d 
	done
fi

# Create and fill run* directories
echo "Creating and filling run*/ directories..."
for ((b=1; b <= $nprocess ; b++)); do
	let "c=((1-1)*$nprocess+$b)"
	mkdir -p run$c

	# Copy ins-files and info on latest commit associated with guess binary
	cp *.ins run$c
	if [[ -e latest_commit.txt ]]; then
		cp latest_commit.txt run$c
	fi

	# Clear out any existing logs and gridlists
	rm -f run$c/guess.log
	rm -f run$c/$gridlist_filename
done
echo " "

# Set up state directory
state_path_relative=$(get_state_dir.sh "${insfile}" | sed 's@%Y@@' | sed "s@//@/@g")
if [[ "${state_path_relative}" != "" ]]; then
	if [[ "$(echo $state_path_relative | head -c 1)" == "/" ]]; then
		# You actually provided an absolute state path
		state_path_absolute="${state_path_relative}"
		state_path_relative="../state/%Y"
		mkdir -p state
	else
		state_path_absolute="$(realpath "run1/${state_path_relative}")"
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

# Split gridlist up into files for each process
lines_per_run=$(wc -l $gridlist | awk '{ x = $1/'$nprocess'; d = (x == int(x)) ? x : int(x)+1; print d}')
split -a 4 -l $lines_per_run $gridlist tmpSPLITGRID_
files=$(ls tmpSPLITGRID_*)
i=1
for file in $files; do
	let "c=((1-1)*$nprocess+$i)"
	mv $file run$c/$gridlist_filename
	i=$((i+1))
done

cat<<EOL > startguess.sh 
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

set -e

/home/kit/imk-ifu/lr8247/scripts_peter/module.sh

cd $rundir_top 
date +%F\ %H:%M:%S > $rundir_top/RUN_INPROGRESS
echo \$(date) \$PWD job $SLURM_JOBID started >> ~/lpj-model-runs.txt
mpirun -print-rank-map -prepend-rank -n $nprocess ${scripts_dir}/mpi_run_guess_on_tmp.sh $rundir_top/$binary "${state_path_relative}" "${state_path_absolute}" -parallel -input $input_module ${insfile}
LASTERR=\$?
rm $rundir_top/RUN_INPROGRESS
[[ \$LASTERR != 0 ]] && date +%F\ %H:%M:%S > $rundir_top/RUN_FAILED

exit 0

EOL

chmod +x startguess.sh

echo "To submit:"
echo "cd $rundir_top"
echo "source ~/scripts_peter/module.sh 1>/dev/null 2>&1"
echo "jobID=\$(sbatch --mail-type=ALL startguess.sh /| sed 's/[^0-9]//g'); echo \$jobID; job_finish.sh -d \$jobID -t ${finishup_t_min} -p ${finishup_nprocs} -N ${jobname}"

exit 0
