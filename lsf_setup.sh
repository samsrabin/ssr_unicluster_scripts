#!/bin/bash
set -e

reservation=""
#reservation="-r landsymm-project"
realinsfile="main.ins"
#testinsfile="main_test2.ins"; testnproc=1
testinsfile="main_test1_fast.ins"; testnproc=1
#testinsfile="main_test2x2.ins"; testnproc=2
#testinsfile="main_test160x3.ins"; testnproc=160
inputmodule="cfx"
walltime_hist="48:00:00"
walltime_fut="48:00:00"  # Should take around ??? hours
walltime_minutes_max=4320
round_walltime_to_next=30        # minutes
walltime_pot_minutes_minimum=90  # 160 processes, Unicluster
walltime_pot_minutes_peryr=3.4   # 160 processes, Unicluster
hist_y1=1850
future_y1=2015
maxNstates=3
future_yN=2100 # Because last year of emulator output is 2084
Nyears_getready=2

#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="lsf_setup.sh"
function usage {
    echo " "
    echo -e "usage: $script [-t]\n"
}

# Set default values for non-positional arguments
arch="landsymm-dev-forestry"
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
ssp_list="hist ssp126 ssp370 ssp585"
Nyears_pot=99999
#Nyears_pot=100
first_pot_y1=1850
last_pot_y1=999999999
pot_step=20
pot_yN=2100
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
        --yN-pot)  shift
            pot_yN=$1
            ;;
        --step-pot)  shift
            pot_step=$1
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

# Process memory specification
. "${HOME}/scripts/process_slurm_mem_spec.sh"

if [[ "${dirForPLUM}" != "" && ! -d "${dirForPLUM}" ]]; then
    echo "dirForPLUM does not exist: ${dirForPLUM}"
    exit 1
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

. lsf_get_years.sh
. lsf_helper_functions.sh

#############################################################################################

echo " "
date
echo " "

while [[ ! -d template ]]; do
    cd ../
    if [[ "$PWD" == "/" ]]; then
        echo "lsf_setup.sh must be called from a (subdirectory of a) directory that has a template/ directory"
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

# Set up/start a run for each set of save years
while IFS= read -r save_years; do

    # First year in this this determines whether we're in the historical
    # period or not
    first_save_year=$(echo ${save_years} | cut -d" " -f1)

    if [[ ${first_save_year} -le ${hist_yN} ]]; then

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
            thisSSP=""
            . lsf_1_acthist.sh
        fi

        # Set up/submit potential historical run(s)
        if [[ ${actual_only} -eq 0 ]]; then
            thisSSP="hist"
            . lsf_setup_potential_loop.sh
        fi
    else
        for thisSSP in ${ssp_list}; do
            if [[ "${thisSSP}" != "hist" && "${thisSSP:0:3}" != "ssp" ]]; then
                thisSSP="ssp${thisSSP}"
            fi
            this_prefix="${prefix}_${thisSSP}"

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

echo dependency a ${dependency}

                . lsf_1_actfut.sh
                popdq
            fi # if doing future-actual

            if [[ ${actual_only} -eq 0 ]]; then
                . lsf_setup_potential_loop.sh
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
