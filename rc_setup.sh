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
walltime_hist="12:00:00"
walltime_fut="12:00:00"  # Should take around ??? hours
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
elif [[ "${runtype}" == "lsa" || "${runtype}" -eq "sai" ]]; then
    # LandSyMM agriculture (incl. SAI-LandSyMM)
    arch="landsymm-dev-crops"
    first_pot_y1=1955
    pot_step=5
    Nyears_pot=5
    Nyears_getready=1
    walltime_pot_minutes_peryr=3.4   # 2022-11-03: For now, assuming the same time as lsf
    walltime_pot_minutes_minimum=45  # 2022-11-04: A guess
else
    echo "runtype must be either lsf, lsa, or sai." >&2
    exit 1
fi
if [[ "${runtype}" -eq "sai" ]]; then
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

# Args while-loop
while [ "$1" != "" ];
do
    case $1 in
        -a  | --actual-only)
            actual_only=1
            ;;
        -n  | --nproc) shift
            nproc="$1"
            ;;
        -p  | --potential-only)
            potential_only=1
            ;;
        -s  | --submit)
            submit="--submit"
            ;;
        -t  | --test)
            istest=1
            ;;
        --arch) shift
            arch="$1"
            ;;
        --fu)
            arg_yes_fu=1
            ;;
        --no-fu)
            arg_no_fu=1
            ;;
        --fu-only)
            do_fu_only=1
            ;;
        --dirForPLUM)  shift
            dirForPLUM="$1"
            ;;
        --ssp-list)  shift
            ssp_list="$1"
            ;;
        --mem-per-node)  shift
            mem_per_node=$1
            ;;
        --mem-per-cpu)  shift
            mem_per_cpu=$1
            ;;
        --nyears-pot)  shift
            Nyears_pot=$1
            ;;
        --first-y1-pot)  shift
            first_pot_y1=$1
            ;;
        --last-y1-pot)  shift
            last_pot_y1=$1
            ;;
        --future-yN)  shift
            future_yN=$1
            ;;
        --yN-pot)  shift
            pot_yN=$1
            ;;
        --step-pot)  shift
            pot_step=$1
            ;;
        --first-y1-act)  shift
            first_act_y1=$1
            ;;
        --max-N-states)  shift
            maxNstates=$1
            ;;
        -d | --dependency)  shift
            dependency_in="-d $1"
            ;;
        *)
            echo "$script: illegal option $1"
            usage
            exit 1 # error
            ;;
    esac
    shift
done

if [[ ${first_act_y1} -lt ${hist_y1} ]]; then
    echo "--first-y1-act (${first_act_y1}) must be >= ${hist_y1}"
    exit 1
fi

# Process memory specification
. "${HOME}/scripts/process_slurm_mem_spec.sh"

# Set up dirForPLUM
if [[ "${dirForPLUM}" != "" && ! -d "${dirForPLUM}" ]]; then
    echo "dirForPLUM does not exist: ${dirForPLUM}"
    exit 1
elif [[ "${dirForPLUM}" == "" ]]; then
    runset_workdir="$(get_equiv_workdir.sh "$PWD")"
    if [[ ${istest} -eq 1 ]]; then
        runset_workdir+="_test"
    fi
    dirForPLUM=${runset_workdir}/outputs/outForPLUM-$(date "+%Y-%m-%d-%H%M%S")
    mkdir -p ${dirForPLUM}
    echo "Top-level output directory: $dirForPLUM"
    echo " "
fi

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
. lsf_helper_functions.sh

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

        s=-1
        for thisSSP in ${ssp_list}; do
            s=$((s + 1))
            if [[ ${runtype} != "sai" && "${thisSSP}" != "hist" && "${thisSSP:0:3}" != "ssp" ]]; then
                thisSSP="ssp${thisSSP}"
            fi
            this_prefix="${prefix}_${thisSSP}"

            # Start 2015-resuming potential runs, if needed
            first_pot_y1=$(echo ${list_pot_y1_future} | cut -d" " -f1)
            if [[ ( ( ${first_save_year} != "" && ${first_pot_y1} -lt ${first_save_year} ) || ${potential_only} -eq 1 ) && ${did_resume_pre2015pots[s]} == 0 && ${thisSSP} != "hist" ]]; then
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
