#!/bin/bash
set -e

reservation=""
#reservation="-r landsymm-project"
realinsfile="main.ins"
testinsfile="main_test2.ins"; testnproc=1
#testinsfile="main_test1_fast.ins"; testnproc=1
#testinsfile="test3x40.ins"; testnproc=40
#testinsfile="main_test2x2.ins"; testnproc=2
#testinsfile="main_test160x3.ins"; testnproc=160
inputmodule="cfx"
walltime_minutes_max=4320
round_walltime_to_next=30        # minutes
hist_y1=1850

#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="rc_setup.sh"
function usage {
    echo " "
    echo -e "usage: $script runtype [-t]\n"
}

# Get runtype and set default arguments
runtype="$1"
shift
if [[ "${runtype}" == "" ]]; then
    echo "You must provide runtype (lsf, lsa, or sai)." >&2
    exit 1
elif [[ "${runtype}" == "lsf" ]]; then
    # LandSyMM forestry
    arch="landsymm-dev-forestry"
    first_pot_y1=1850
    pot_step=20
    Nyears_getready=2
    Nyears_pot=99999
    walltime_pot_minutes_peryr=3.4   # 160 processes, Unicluster
    walltime_pot_minutes_minimum=90  # 160 processes, Unicluster
    walltime_hist="12:00:00"
    walltime_fut="12:00:00"  # Should take around ??? hours
elif [[ "${runtype}" == "lsa" || "${runtype}" == "sai" ]]; then
    # LandSyMM agriculture
    arch="landsymm-dev-crops"
    first_pot_y1=2000
    pot_step=5
    Nyears_pot=5
    Nyears_getready=2
    if [[ "${runtype}" == "lsa" ]]; then
        walltime_pot_minutes_peryr=5.0
        walltime_pot_minutes_minimum=90
        walltime_hist="18:00:00"
        walltime_fut="18:00:00"
    elif [[ "${runtype}" -eq "sai" ]]; then
        walltime_pot_minutes_peryr=3.4
        walltime_pot_minutes_minimum=45
        walltime_hist="12:00:00"
        walltime_fut="12:00:00"
    fi
else
    echo "runtype must be either lsf, lsa, or sai." >&2
    exit 1
fi
if [[ "${runtype}" == "sai" ]]; then
    ssp_list="hist ssp245 arise1.5"
    future_y1=2035
else
    ssp_list="hist ssp126 ssp370 ssp585"
    future_y1=2015
fi


# Set default values for non-positional arguments
future_yN=2100
istest=0
arg_yes_fu=0
arg_no_fu=0
do_fu_only=0
submit=""
dirForPLUM=""
dependency_in=""
actual_only=0
potential_only=0
nproc=160
#Nyears_pot=100
first_act_y1=${hist_y1}
last_pot_y1=999999999
pot_yN=2100
maxNstates=3
# Handle possible neither/both specs here
mem_per_node_default=90000 # MB
mem_per_node=-1 # MB
mem_per_cpu_default=500 # MB
mem_per_cpu=-1 # MB
reservation=""
gcm_in=""
isimip3_climate_dir=""

# Get default LPJ-GUESS code location
if [[ "${LPJG_TOPDIR}" == "" ]]; then
    echo "Environment variable LPJG_TOPDIR is blank; will rely on --lpjg_topdir argument." >&2
elif [[ ! -d "${LPJG_TOPDIR}" ]]; then
    echo "LPJG_TOPDIR not found: ${LPJG_TOPDIR}" >&2
    echo "Will rely on --lpjg_topdir argument." >&2
else
    lpjg_topdir="${LPJG_TOPDIR}"
fi

# Args while-loop
while [ "$1" != "" ];
do
    case $1 in

        # Only submit "actual" runs
        -a  | --actual-only)
            actual_only=1
            ;;

        # SAI runs only: Ensemble member to use for all segments unless counteracted by ensemble_member_hist and/or ensemble_member_fut
        -e  | --ensemble-member) shift
            ensemble_member="$1"
            ;;

        # SAI runs only: Ensemble member to use for historical period
        --ensemble-member-hist) shift
            ensemble_member_hist="$1"
            ;;

        # SAI runs only: Ensemble member to use for future segments
        --ensemble-member-fut) shift
            ensemble_member_fut="$1"
            ;;

        # Number of processors to use
        -n  | --nproc) shift
            nproc="$1"
            ;;

        # Only submit "potential" runs
        -p  | --potential-only)
            potential_only=1
            ;;

        # Submit the runs instead of just setting up directories
        -s  | --submit)
            submit="--submit"
            ;;

        # Do a "test" chain instead of the real thing. Uses $testinsfile instead of $realinsfile (see top of script)
        -t  | --test)
            istest=1
            ;;

        # The name of the directory in $LPJG_TOPDIR (or --lpjg_topdir) where the guess executable can be found. Well, mostly. For --arch XXXX, the name of the directory should be build_XXXX.
        --arch) shift
            arch="$1"
            ;;

        # Submit "finish-up" (postprocessing) scripts to run after each segment completes. That's the default behavior except for -t/--test runs.
        --fu)
            arg_yes_fu=1
            ;;

        # Do not submit "finish-up" (postprocessing) scripts.
        --no-fu)
            arg_no_fu=1
            ;;

        # ONLY submit "finish-up" (postprocessing) scripts.
        --fu-only)
            do_fu_only=1
            ;;

        # Directory where you want files postprocessed for PLUM to go. This is useful if, for example, you did a chain with ssp-list "hist ssp126", and now you want to do --ssp-list "ssp585"—in the latter, you point --dirForPLUM to the postprocessing-output directory from the former.
        --dirForPLUM)  shift
            dirForPLUM="$1"
            ;;

        # SSPs (also "hist" historical period) to run
        --ssp-list)  shift
            ssp_list="$1"
            ;;

        # Memory to be used on each node.
        --mem-per-node)  shift
            mem_per_node=$1
            ;;

        # Memory to be assigned to each CPU.
        --mem-per-cpu)  shift
            mem_per_cpu=$1
            ;;

        # The number of years in each potential period (excluding Nyears_getready).
        --nyears-pot)  shift
            Nyears_pot=$1
            ;;

        # The first year that any potential run should start with (excluding Nyears_getready).
        --first-y1-pot)  shift
            first_pot_y1=$1
            ;;

        # The last year that any potential run should start with.
        --last-y1-pot)  shift
            last_pot_y1=$1
            ;;

        # The first year in the future period.
        --future-y1)  shift
            future_y1=$1
            ;;

        # The last year in the future period.
        --future-yN)  shift
            future_yN=$1
            ;;

        # The last year that any potential run should end with.
        --yN-pot)  shift
            pot_yN=$1
            ;;

        # The number of years between starts of consecutive potential runs.
        --step-pot)  shift
            pot_step=$1
            ;;

        # The first year that should be run in "actual" runs. Default ${hist_y1}.
        --first-y1-act)  shift
            first_act_y1=$1
            ;;

        # The maximum number of states to be saved per actual run. Higher values here increase the risk of weird errors related to disks running out of space or something.
        --max-N-states)  shift
            maxNstates=$1
            ;;

        # -d JOBNUM: Wait to submit the first run in this chain until JOBNUM completes.
        -d | --dependency)  shift
            dependency_in="-d $1"
            ;;

        # If you ask the admins nicely, they'll grant you a "reservation"---some nodes you get all to yourself. Specify "-r RESERVATION_NAME" (no quote marks) to use
        -r | --reservation) shift
            reservation="--reservation $1"
            ;;

        # Directory with your LPJ-GUESS codebase, where build_${arch} will be looked for
        --lpjg_topdir )  shift
            lpjg_topdir=$1
            ;;

        # GCM to use
        -g | --gcm) shift
            gcm_in="$1"
            ;;

        # ISIMIP3 climate directory to use
        --isimip3-climate-dir) shift
            isimip3_climate_dir="$1"
            ;;

        *)
            echo "$script: illegal option $1"
            usage
            exit 1 # error
            ;;
    esac
    shift
done

if [[ "${lpjg_topdir}" == "" ]]; then
    echo "You must specify --lpjg_topdir" >&2
    echo "You could also do the following: export LPJG_TOPDIR=/path/to/lpj-guess/code" >&2
    echo "either in this terminal or in ~/.bash_profile" >&2
    exit 1
elif [[ ! -d "${lpjg_topdir}" ]]; then
    echo "lpjg_topdir not found: ${lpjg_topdir}" >&2
    exit 1
fi

if [[ ${first_act_y1} -lt ${hist_y1} ]]; then
    echo "--first-y1-act (${first_act_y1}) must be >= ${hist_y1}"
    exit 1
fi

if [[ "${gcm_in}" != "" ]]; then
    if [[ "${runtype}" != "lsa" ]]; then
        echo "-g/--gcm currently only supported for runtype lsa (not ${runtype})" >&2
        exit 1
    fi
fi

# Process memory specification
. "${HOME}/scripts/process_slurm_mem_spec.sh"

# Do finishup or no?
if [[ ${do_fu_only} -eq 1 ]]; then
    if [[ ${arg_no_fu} == "1" ]]; then
        echo "Both --fu-only and --no-fu specified; choose one."
        exit 1
    fi
    do_fu=1
elif [[ ${arg_no_fu} == "1" && ${arg_yes_fu} == "1" ]]; then
    if [[ ${istest} -eq 1 ]]; then
        echo "Both --fu and --no-fu specified. Using dev default of NO finishup."
        do_fu=0
    else
        echo "Both --fu and --no-fu specified. Using non-dev default of YES finishup."
        do_fu=1
    fi
elif [[ ${arg_no_fu} == "1" ]]; then
    do_fu=0
elif [[ ${istest} -eq 1 ]]; then
    if [[ ${arg_yes_fu} == "1" ]]; then
        do_fu=1
    else
        do_fu=0
    fi
elif [[ ${arg_no_fu} == "1" ]]; then
    do_fu=0
else
    do_fu=1
fi

#############################################################################################

# Process test vs. real thing
if [[ ${istest} -eq 1 ]]; then
    topinsfile=${testinsfile}
    walltime_hist="30:00"
    walltime_fut="30:00"
    nproc=${testnproc}
    ppfudev="--dev"
    if [[ $do_fu_only -eq 1 ]]; then
        ppfudev="--dev --fu_only"
    elif [[ $do_fu -eq 1 ]]; then
        ppfudev="--dev --fu"
    fi
    reservation=""
#    maxNstates=999
else
    topinsfile=${realinsfile}
    if [[ $do_fu_only -eq 1 ]]; then
        if [[ $do_fu -eq 0 ]]; then
            echo "Both --fu-only and --no-fu specified; choose one."
            exit 1
        fi
        ppfudev="--fu_only"
    fi
    if [[ $do_fu -eq 0 ]]; then
        ppfudev="--no_fu"
    fi
fi

# Are we actually submitting historical period?
if [[ $(echo ${ssp_list} | cut -f1 -d" ") == "hist" ]]; then
    do_hist=1
else
    do_hist=0
fi

# We don't need hist in the SSP list anymore
if [[ ${do_hist} -eq 1 ]]; then
    ssp_list="$(echo ${ssp_list} | sed "s/hist//")"
fi

# Future period?
if [[ "${ssp_list/ /}" == "" ]]; then
    do_future=0
else
    do_future=1
fi


#############################################################################################

. rc_get_years.sh
. rc_helper_functions.sh

#############################################################################################

echo " "
date
echo " "

while [[ ! -d template ]]; do
    cd ../
    if [[ "$PWD" == "/" ]]; then
        echo "rc_setup.sh must be called from a (subdirectory of a) directory that has a template/ directory"
        exit 1
    fi
done

# Do we need to specify climate directory?
if [[ $(grep "ISIMIP3CLIMATEDIR" template/main.ins | wc -l) -gt 0 && "${isimip3_climate_dir}" == "" ]]; then
    if [[ "${runtype}" == "lsa" ]]; then
        isimip3_climate_dir="/pfs/work7/workspace/scratch/xg4606-isimip3_climatev2"
    else
        echo "Specify --isimip3-climate-dir" >&2
        exit 1
    fi
fi

# Get GCM synonyms and ensemble member info, if needed.
# Then set up subdirectory.
if [[ $(grep "GCMLONG\|ENSEMBLEMEMBER" template/main.ins | wc -l) -gt 0 ]]; then
    if [[ "${runtype}" == "sai" ]]; then
        if [[ "${ensemble_member}" == "" ]]; then
            echo "For sai run chains, you must provide an ensemble member." >&2
            exit 1
        fi
        arise_included=$([[ "${ssp_list}" == *"arise"* ]] && echo 1 || echo 0)
        ssp_included=$([[ "${ssp_list}" == *"ssp"* ]] && echo 1 || echo 0)
        future_included=$((arise_included + ssp_included))
        # Handle historical-period ensemble member (needed for future-only runs too)
        # Get ensemble_member_hist
        if [[ "${ensemble_member_hist}" == "" ]]; then
            if [[ "${ensemble_member}" == "" ]]; then
                echo "For sai run chains, you must provide -e|--ensemble-member[-hist]." >&2
                exit 1
            fi
            ensemble_member_hist="${ensemble_member}"
        fi
        # Check for valid value
        if [[ ( "${ensemble_member_hist}" -lt 1 || "${ensemble_member_hist}" -gt 3 ) ]]; then
            echo "For sai run chains, historical ensemble member must be between 1 and 3 (inclusive)." >&2
            exit 1
        fi
        # Handle future-period ensemble member
        if [[ ${future_included} -gt 0 ]]; then
            # Get ensemble_member_fut
            if [[ "${ensemble_member_fut}" == "" ]]; then
                if [[ "${ensemble_member}" == "" ]]; then
                    echo "For SSP list containing future period, you must provide -e|--ensemble-member[-fut]." >&2
                    exit 1
                fi
                ensemble_member_fut="${ensemble_member}"
            fi
            # Check for valid value
            if [[ ( "${ensemble_member_fut}" -lt 1 || "${ensemble_member_fut}" -gt 10 ) ]]; then
                echo "For sai run chains, future ensemble member must be between 1 and 10 (inclusive)." >&2
                exit 1
            fi
        fi
        # Left-pad with zeros to length 3
        ensemble_member_hist=$(printf "%03d" ${ensemble_member_hist})
        [[ ${future_included} -gt 0 ]] && ensemble_member_fut=$(printf "%03d" ${ensemble_member_fut})
    else
        if [[ "${ensemble_member}${ensemble_member_hist}${ensemble_member_fut}" != "" ]]; then
            echo "Do not specify ensemble member(s) for ${runtype} run chains; they are determined automatically." >&2
            exit 1
        fi
        if [[ "${gcm_in}" == "" ]]; then
            echo "Specify -g/--gcm" >&2
            exit 1
        elif [[ "${isimip3_climate_dir}" == "" ]]; then
            echo "Specify --isimip3-climate-dir" >&2
            exit 1
        fi
        . rc_get_gcm_info.sh

        mkdir -p ${gcm_long_lower}_${ensemble_member}
        cd ${gcm_long_lower}_${ensemble_member}
        if [[ -e template ]]; then
            rm template
        fi
        ln -s ../template
    fi
fi

# Get run set working directory
runset_workdir="$(get_equiv_workdir.sh "$PWD")"
if [[ ${istest} -eq 1 ]]; then
    runset_workdir+="_test"
fi

# Set up dirForPLUM
if [[ "${dirForPLUM}" != "" && ! -d "${dirForPLUM}" ]]; then
    echo "dirForPLUM does not exist: ${dirForPLUM}"
    exit 1
elif [[ "${dirForPLUM}" == "" ]]; then
    dirForPLUM=${runset_workdir}/outputs/outForPLUM-$(date "+%Y-%m-%d-%H%M%S")
    mkdir -p ${dirForPLUM}
    echo "Top-level output directory: $dirForPLUM"
    echo " "
fi

# Get name of runset
runsetname="$(basename "$(realpath .)")"

# Set up job arrays
arr_job_name=()
arr_job_num=()
arr_y1=()
arr_yN=()

# Get job name prefix
prefix="$(lsf_chain_shortname.sh $(basename ${PWD}) ${istest})"


#########################################
### Set up "actual" historical run(s) ###
#########################################

previous_act_jobnum=
mkdir -p actual
act_restart_year=

did_resume_pre2015pots=()
for thisSSP in ${ssp_list}; do
    if [[ ${first_pot_y1} -le ${future_y1} ]]; then
        did_resume_pre2015pots+=(0)
    else
        did_resume_pre2015pots+=(-1)
    fi
done

if [[ "${save_years_lines}" == "" ]]; then
    if [[ ${actual_only} -eq 1 ]]; then
        echo "-a/--actual only, but save_years_lines is empty" >&2
    else
        echo "If you only want potential runs, specify -p/--potential-only so that save_years_lines is correctly filled." >&2
    fi
    exit 1
fi

# Set up/start a run for each set of save years
N_future_periods=0
while IFS= read -r save_years; do

    # First year in this this determines whether we're in the historical
    # period or not
    first_save_year=$(echo ${save_years} | cut -d" " -f1)

    if [[ ${first_save_year} != "" && ${first_save_year} -le ${hist_yN} ]]; then

        thisSSP="hist"

        # Sanity check
        if [[ ${do_hist} == 0 ]]; then
            echo "do_hist 0 but save_years ${save_years}"
            exit 1
        fi

        # Set up/submit actual historical run(s)
        if [[ ${potential_only} -eq 0 ]]; then
            if [[ "${dependency_on_latest_potset}" != "" ]]; then
                dependency="${dependency_on_latest_potset}"
            else
                dependency="${dependency_in}"
                if [[ ${previous_act_jobnum} != "" ]]; then
                    dependency+=" -d ${previous_act_jobnum}"
                fi
            fi # if this is the first future-actual
            . rc_1_acthist.sh
        fi

        # Set up/submit potential historical run(s)
        if [[ ${actual_only} -eq 0 ]]; then
            pot_years="${save_years}"
            resume_pre2015pots=0
            echo rc_setup_potential_loop.sh A
            . rc_setup_potential_loop.sh
            save_years=${future_y1}
        fi
    else
        N_future_periods=$((N_future_periods + 1))
        if [[ ${N_future_periods} -eq 1 && ${act_restart_year} != "" ]]; then
            act_restart_year_eachSSP_array=()
            for thisSSP in ${ssp_list}; do
                act_restart_year_eachSSP_array+=( ${act_restart_year} )
            done
        fi

        s=-1
        for thisSSP in ${ssp_list}; do
            if [[ ${N_future_periods} -eq 1 ]]; then
                act_restart_year=""
            fi
            s=$((s + 1))
            if [[ ${runtype} != "sai" && "${thisSSP}" != "hist" && "${thisSSP:0:3}" != "ssp" ]]; then
                thisSSP="ssp${thisSSP}"
            fi
            this_prefix="${prefix}_${thisSSP}"

            # Start 2015-resuming potential runs, if needed
            if [[ "${first_pot_y1}" == "" ]]; then
                first_pot_y1=$(echo ${list_pot_y1_future} | cut -d" " -f1)
            fi
            if [[ ( ( ${first_save_year} != "" && ${first_pot_y1} -lt ${first_save_year} ) || ${potential_only} -eq 1 ) && ${did_resume_pre2015pots[s]} == 0 && ${thisSSP} != "hist" && ${actual_only} -eq 0 ]]; then
                resume_pre2015pots=1
                echo rc_setup_potential_loop.sh B
                . rc_setup_potential_loop.sh
                did_resume_pre2015pots[s]=1
            fi

            if [[ ${potential_only} -eq 0 && ${do_future_act} -eq 1 ]]; then
                pushdq "actual"
                if [[ "${dependency_on_latest_potset}" != "" ]]; then
                    dependency="${dependency_on_latest_potset}"
                else
                    dependency="${dependency_in}"
                    if [[ ${previous_act_jobnum} != "" ]]; then
                        dependency+=" -d ${previous_act_jobnum}"
                    fi
                fi # if this is the first future-actual

                . rc_1_actfut.sh
                popdq
            fi # if doing future-actual

            if [[ ${actual_only} -eq 0 && "${save_years}" != "" ]]; then
                pot_years="${save_years}"
                resume_pre2015pots=0
                echo rc_setup_potential_loop.sh C
                . rc_setup_potential_loop.sh
            fi
        done # loop through SSPs
    fi # whether in historical or future period
done <<< ${save_years_lines}


echo arr_job_name ${arr_job_name[@]}
echo arr_job_num ${arr_job_num[@]}
echo arr_y1 ${arr_y1[@]}
echo arr_yN ${arr_yN[@]}

squeue -o "%10i %.7P %.35j %.10T %.10M %.9l %.6D %.16R %E" -S JOBID | sed "s/unfulfilled/unf/g"

exit 0
