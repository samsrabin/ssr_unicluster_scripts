#!/bin/bash
set -e

if [[ "$#" -eq "0" ]]; then
    echo "usage:"
    echo "  `basename $0` <maininsfile> "other_ins_files" <grid> <input_module> <np> <imac|keam|linux|scc>"
    exit
fi

#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="lsf_setup_1run.sh"
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
echo -e "  -L --linked_restart_dir PATH Path to restart directory (.../state/YEAR) that will be linked in this state_path_absolute"
echo -e "  -p --prefix VAL  Add VAL to beginning of Slurm job names\n"
echo -e "  -s --state_path_absolute VAL Absolute path to state directory, if path in ins-files can't be trusted\n"
echo -e "  -r --reservation VAL Job reservation name\n"
echo -e "  --no_fu Do not start finishup job\n"
echo -e "  --fu DO start finishup job (which is off by default with --dev)\n"
echo -e "  --fu_only ONLY start finishup job\n"
echo -e "  --dev                           Use one of the dev queues. Add --fu to also start a postprocessing job.\n"
echo -e "  --submit                      Go ahead and submit the job (and postprocessing, if applicable).\n"
echo -e "  --lpjg_topdir The complete path to the directory containing the build dir.\n"
echo -e "  -h,  --help                 Prints this help\n"
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
do_finishup_only=0
arg_yes_fu=
arg_no_fu=
submit=0
reservation=
linked_restart_dir_array=()
pp_y1=
pp_yN=
lpjg_topdir=$HOME/lpj-guess_git-svn_20190828
delete_state_year=
# Handle possible neither/both specs here
mem_per_node_default=90000 # MB
mem_per_node=-1 # MB
mem_per_cpu_default=1000 # MB
mem_per_cpu=-1 # MB

# Args while-loop
while [ "$1" != "" ];
do
    case $1 in
        -d  | --dependency)  shift
            dependency_tmp+=" $1"
            ;;
        --dependency-name)  shift
            dependency_name=$1
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
        --lpjg_topdir)  shift
            lpjg_topdir=$1
            ;;
        --pp_y1)  shift
            pp_y1=$1
            ;;
        --pp_yN)  shift
            pp_yN=$1
            ;;
        --mem-per-node)  shift
            mem_per_node=$1
            ;;
        --mem-per-cpu)  shift
            mem_per_cpu=$1
            ;;
        --dev)  dev=1
            ;;
        --fu)  arg_yes_fu=1
            ;;
        --no_fu)  arg_no_fu=1
            ;;
        --fu_only)  do_finishup_only=1
            ;;
        --submit)  submit=1
            ;;
        --delete-state-year)  shift
            delete_state_year=$1
            ;;
        -h    | --help )          help
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

# Parse dependency
if [[ "${dependency_tmp}" != "" ]]; then
    dependency="#SBATCH"
    for d in ${dependency_tmp}; do
        if [[ "${d}" == "LATEST" ]]; then
            d=$(awk 'END {print $NF}' ~/submitted_jobs.log)
            echo "Using latest submitted job (${d}) as dependency"
        else
            echo "Depending on job ${d}"
        fi
        dependency+=" -d afterany:$d"
    done
fi
if [[ "${dependency_name}" != "" ]]; then
    echo "I.e., depending on ${dependency_name}"
fi

# Process memory specification
. "${HOME}/scripts/process_slurm_mem_spec.sh"

# Do finishup or no?
if [[ ${do_finishup_only} -eq 1 ]]; then
    if [[ ${arg_no_fu} == "1" ]]; then
        echo "Both --fu_only and --no_fu specified; choose one."
        exit 1
    fi
elif [[ ${arg_no_fu} == "1" && ${arg_yes_fu} == "1" ]]; then
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

# Are we in an actual, potential, or calibration run?
if [[ $PWD == *"/actual/"* ]]; then
    whichrun="act"
elif [[ $PWD == *"/potential/"* ]]; then
    whichrun="pot"
elif [[ $PWD == *"/calibration"* ]]; then
    whichrun="cal"
else
    echo "Can't parse this path to tell whether it's an actual or potential run"
    echo pwd $PWD
    exit 1
fi

# Get name of this runset
runsetname=$(lsf_get_runset_name.sh)
if [[ "${runsetname}" == "" ]]; then
    echo "runsetname is blank"
    exit 1
fi
if [[ $PWD == *calibration* ]]; then
    runsetname="calibration"
else
    runsetname=$(lsf_get_basename.sh)
fi

# Get directories, modifying paths if testing
if [[ "${whichrun}" == "pot" ]]; then
    runid=$(echo $PWD | grep -oE "[0-9]+pot.*" | sed -E "s/_[0-9]+-[0-9]+//" | sed "s/_ssp//")
else
    runid=$(basename $PWD)
fi
jobname=${runid}_$(date "+%Y%m%d%H%M%S")
if [[ ${prefix} != "" ]]; then
    jobname=${prefix}_${jobname}
fi
rundir_top=$(lsf_get_rundir_top.sh ${dev})
if [[ "${rundir_top}" == "" ]]; then
    echo "Error finding rundir_top; exiting."
    exit 1
fi

if [[ ${dev} -eq 1 ]]; then
    if [[ "${linked_restart_dir_array}" != "" ]]; then
        for i in "${!linked_restart_dir_array[@]}"; do 
            lrd=${linked_restart_dir_array[$i]}
            lrd=$(echo ${lrd} | sed "s@${runsetname}@${runsetname}_test@")
            linked_restart_dir_array[$i]=${lrd}
        done
    fi
fi
state_path_absolute=$(lsf_get_state_path_absolute.sh "${rundir_top}" "${state_path_absolute}")

# End function-parsing code
#############################################################################################

# For running on UniCluster
cores_per_node=40 #uc2 nodes, 40 cores with hyperthreading *2. 
#cores_per_node=32 # Running out of memory again, so trying 32 instead of 40
#tasks_per_core=2 # Ends up running out of memory...
tasks_per_core=1
tasks_per_node=$((cores_per_node*tasks_per_core))
finishup_t_min=60
if [[ ${nprocess} -gt ${tasks_per_node} ]]; then
    # Round up if nprocess isn't a multiple of tasks_per_node
    nnodes=$(((nprocess+tasks_per_node-1)/tasks_per_node))
    if [[ $((nprocess%tasks_per_node)) != 0 ]]; then
        echo "nprocess (${nprocess}) not a multiple of ${tasks_per_node}; still requesting ${nnodes} exclusive nodes."
    fi
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

if [[ ${do_finishup_only} -eq 0 ]]; then
    echo "queue: ${queue}"
    echo "nprocess: ${nprocess}"
    echo "nnodes: ${nnodes}"
    echo "walltime: ${walltime}"
fi
echo "finishup_partition: ${finishup_partition}"
echo "finishup_nprocs: ${finishup_nprocs}"

lpjg_dir=${lpjg_topdir}/build_$arch
#scripts_dir=/pfs/data1/home/kit/imk-ifu/lr8247/scripts
scripts_dir=$HOME/scripts
binary=guess
########################################################################

gridlist_filename=$(basename $gridlist)

#============================================================== ... split to nodes======================

USER=$(whoami)

# ============================================================ prepare work dir ... ===================

mkdir -p "${rundir_top}"
echo "rundir_top = ${rundir_top}"
if [[ -e postproc.sh ]]; then
    cp postproc.sh $rundir_top/
fi

if [[ ${do_finishup_only} -eq 0 ]]; then
    
    #======Copy ins, gridlist and executable
    
    rsync -a  $lpjg_dir/$binary $rundir_top
    
    # SSR 2017-05-30
    if [[ -e $lpjg_dir/latest_commit.txt ]]; then
        rsync -a  $lpjg_dir/latest_commit.txt $rundir_top
    fi
    
    # SSR 2021-04-30
    if [[ -e $lpjg_dir/latest_cmake.txt ]]; then
        rsync -a  $lpjg_dir/latest_cmake.txt $rundir_top
    fi
    
    cp $gridlist $rundir_top
    for ins in $insfile $extra_insfiles; do
        cp $ins $rundir_top
    done
    
    cd $rundir_top
    
    # Clear existing run* directories
    set +e
    ls -d run*/ 1> /dev/null 2>&1
    result=$?
    set -e
    if [[ $result == 0 ]]; then
        echo "Removing existing run*/ directories..."
        empty_dir="empty_dir_$(date +%N)/"
        mkdir $empty_dir
        for d in $(ls -d run*/ | grep -E "^run[0-9]+/"); do
            if [[ -d "${d}" ]]; then
    #            # Only try to remove contents if not empty
    #            if [[ ! -z "$(ls -A "${d}")" ]]; then
    #                rm $d/*
    #            fi
    #            rmdir $d
                rsync -a --delete $empty_dir "${d}"/
                rmdir "${d}"
            fi
        done
        rmdir $empty_dir
    fi
    
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
    #    mkdir -p run1/${state_path_relative}
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
        #                  echo     # (optional) move to a new line
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

    delete_state_text=""
    if [[ ${delete_state_year} != "" ]]; then
        delete_state_text="set +e; rm \"${state_path_absolute}/${delete_state_year}\"/*.state"
    fi
    
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

##module unload \$(module -t list 2>&1 | grep "tools\|app\|io\|compiler\|mpi\|lib\|math\|devel\|numlib\|cae\|chem\|system")
##module load compiler/gnu mpi/openmpi
##module list
#/home/kit/imk-ifu/lr8247/scripts_peter/module_gnu.sh
source /home/kit/imk-ifu/lr8247/scripts_peter/module_gnu.sh

# THIS NEEDS 2>&1
echo "modules after calling module_gnu.sh:"
module list

#this requires a locally compiled netcdf with hdf5
export LD_LIBRARY_PATH=\$SOFTWARE/hdf5-1.12.1/lib:\$SOFTWARE/lib:\$LD_LIBRARY_PATH
export HDF5_DISABLE_VERSION_CHECK=1

diagnostics=1
mpirun_options=""
if [[ \$diagnostics -eq 1 ]]; then
    if [[ \$(which mpirun | grep "openmpi" | wc -l) -eq 1 ]]; then
        #mpirun_options="-display-map -tag-output"
        #mpirun_options="--bind-to core --map-by core -report-bindings -display-map -tag-output"
        mpirun_options="--bind-to socket --map-by socket -report-bindings -display-map -tag-output"
    elif [[ \$(which mpirun | grep "intel" | wc -l) -eq 1 ]]; then
        mpirun_options="-print-rank-map -prepend-rank"
    else
        echo "mpirun \$(which mpirun) not recognized; will set no options for stdout/stderr printing"
    fi
fi

echo " "
echo "mpirun_options:"
echo $mpirun_options
echo " "

cd $rundir_top 
date +%F\ %H:%M:%S > $rundir_top/RUN_INPROGRESS
echo \$(date) \$PWD job $SLURM_JOBID started >> ~/lpj-model-runs.txt
mpirun \$mpirun_options -n $nprocess ${scripts_dir}/mpi_run_guess_on_tmp.sh $rundir_top/$binary "${state_path_relative}" "${state_path_absolute}" -parallel -input $input_module ${insfile}
LASTERR=\$?
rm $rundir_top/RUN_INPROGRESS
[[ \$LASTERR != 0 ]] && date +%F\ %H:%M:%S > $rundir_top/RUN_FAILED

${delete_state_text}

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
jobID_finish=\$(job_finish.sh -a ${finishup_partition} -d afterany:\$jobID -t ${finishup_t_min} -p ${finishup_nprocs} -N ${jobname} ${reservation_txt_fu} | sed "s/Submitted batch job //")
if [[ "\${jobID_finish}" == "" ]]; then
    exit 1
fi
echo "job_finish.sh: \$jobID_finish"
echo "job_finish.sh: \$jobID_finish" >> latest_submitted_jobs.log
echo " " >> ~/submitted_jobs.log
EOL
fi
cat<<EOL >> startguess.sh
cat latest_submitted_jobs.log >> ~/submitted_jobs.log
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
        
        if [[ ${dev} -eq 1 ]]; then
            echo " "
            echo "To submit interactively:"
            echo "cd $rundir_top"
            echo "source ~/scripts_peter/module_gnu.sh 1>/dev/null 2>&1"
            echo "salloc --partition $queue -N $nnodes -n $nprocess --ntasks-per-core ${tasks_per_core} -t $walltime ${reservation_txt} submit.sh" 
        fi
    fi


else # do_finishup_only

    #################################################
    # Create script that will submit postprocessing #
    #################################################

    pushd "${rundir_top}" 1>/dev/null 2>&1
    
    cat<<EOL > start_jobfinish.sh
jobID_finish=\$(job_finish.sh -a ${finishup_partition} -t ${finishup_t_min} -p ${finishup_nprocs} -N ${jobname} ${reservation_txt_fu} | sed "s/Submitted batch job //")
if [[ "\${jobID_finish}" == "" ]]; then
    exit 1
fi
echo "job_finish.sh: \$jobID_finish"
echo "job_finish.sh: \$jobID_finish" >> latest_submitted_jobs.log
echo " " >> ~/submitted_jobs.log
cat latest_submitted_jobs.log >> ~/submitted_jobs.log
exit 0
EOL
    chmod +x start_jobfinish.sh


    ####################################################
    # Either submit or print instructions for doing so #
    ####################################################

    if [[ ${submit} -eq 1 ]]; then
        echo "Submitting..."
        source ~/scripts_peter/module_gnu.sh 1>/dev/null 2>&1
        echo pwd $PWD
        ./start_jobfinish.sh
    else
        echo "To submit:"
        echo "cd $rundir_top"
        echo "source ~/scripts_peter/module_gnu.sh 1>/dev/null 2>&1"
        echo "./start_jobfinish.sh"
    fi

    popd 1>/dev/null 2>&1

fi


exit 0
