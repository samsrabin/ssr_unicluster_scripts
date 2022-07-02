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
walltime_pot_minutes_peryr=3.0   # 160 processes, Unicluster
hist_y1=1850
future_y1=2015
maxNstates=3
future_yN=2100 # Because last year of emulator output is 2084
Nyears_getready=2

firstpotyear=$((future_y1 - Nyears_getready - 2*Nyears_pot))

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

# Get info for last XXXXpast_YYYYall_LU.txt
first_LUyear_past=$((first_pot_y1 - Nyears_getready))
last_LUyear_past=${first_LUyear_past}
last_LUyear_all=$((last_LUyear_past + 1))
y1=$((first_pot_y1 + pot_step))
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_y1} ]]; do
    last_LUyear_past=$((last_LUyear_past + pot_step))
    last_LUyear_all=$((last_LUyear_all + pot_step))
    y1=$((y1 + pot_step))
done
hist_yN=$((future_y1 - 1))
last_year_act_hist=$((last_LUyear_past - 1))
do_future_act=0
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_yN} ]]; do
    do_future_act=1
    last_LUyear_past=$((last_LUyear_past + pot_step))
    last_LUyear_all=$((last_LUyear_all + pot_step))
    y1=$((y1 + pot_step))
done
last_year_act_future=$((last_LUyear_past - 1))
if [[ ${do_future_act} -eq 1 ]]; then
    last_year_act_hist=${hist_yN}
fi

# Generate lists of start and end years for potential runs
list_pot_y1_hist=()
list_pot_y1_future=()
list_pot_yN_hist=()
list_pot_yN_future=()
y1=${first_LUyear_past}
yN=$((y1 + Nyears_pot - 1))
if [[ ${yN} -gt ${pot_yN} ]]; then
    yN=${pot_yN}
fi
i=0
list_pot_y0_future=()
while [[ "${ssp_list}" == *"hist"* ]] && [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -le ${last_pot_y1} ]] && [[ ${yN} -lt ${future_y1} ]]; do
    list_pot_y1_hist+=(${y1})

    if [[ ${yN} -ge ${future_y1} ]]; then
        list_pot_yN_hist+=(${hist_yN})
        list_pot_y1_future+=(${future_y1})
        list_pot_yN_future+=(${yN})
        list_pot_y0_future+=(${y1})
        list_pot_save_state+=(1)
    else
        list_pot_yN_hist+=(${yN})
        list_pot_save_state+=(0)
    fi

    y1=$((y1 + pot_step))
    yN=$((y1 + Nyears_pot - 1))
    if [[ ${yN} -gt ${pot_yN} ]]; then
        yN=${pot_yN}
    fi
done
h=-1
list_future_is_resuming=()
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -le ${last_pot_y1} ]] && [[ ${y1} -lt ${future_yN} ]]; do
    list_pot_save_state+=(0)
    yN=$((y1 + Nyears_pot - 1))
    if [[ ${yN} -gt ${pot_yN} ]]; then
        yN=${pot_yN}
    fi

    if [[ ${y1} -lt ${future_y1} ]]; then
        if [[ "${ssp_list}" == *"hist"* ]]; then
            list_pot_y1_hist+=(${y1})
            list_pot_yN_hist+=(${hist_yN})
        fi
        list_pot_y1_future+=(${future_y1})
        list_pot_yN_future+=(${yN})
        list_future_is_resuming+=(1)
        h=$((h+1))
        list_pot_y0_future+=(${y1})
    else
        list_pot_y1_future+=(${y1})
        list_pot_yN_future+=(${yN})
        list_future_is_resuming+=(0)
        list_pot_y0_future+=(9999)
    fi

    y1=$((y1 + pot_step))
done

# Generate lists of states to save in historical and future periods
hist_save_years=
fut_save_years=
if [[ ${potential_only} -eq 0 ]]; then
    if [[ "${ssp_list}" == *"hist"* ]]; then
        hist_save_years="${list_pot_y1_hist[@]}"
    fi
    added_future_y1=0
    i=-1
    for y in ${list_pot_y1_future[@]}; do
        i=$((i+1))
        is_resuming=${list_future_is_resuming[i]}
        if [[ ${is_resuming} -eq 1 ]]; then
            if [[ ${added_future_y1} -eq 0 ]]; then
                hist_save_years+=" ${future_y1}"
                added_future_y1=1
            fi
            continue
        elif [[ ${y} -le ${future_y1} ]]; then
            continue
        fi
        fut_save_years+=" ${y}"
    done

    echo "Saving states in actual runs at beginning of years:"
    echo "    Historical runs:" $hist_save_years
    echo "        Future runs:" $fut_save_years
else
    echo "No actual runs."
fi
echo "Historical potential runs:"
echo "    Begin:" ${list_pot_y1_hist[@]}
echo "      End:" ${list_pot_yN_hist[@]}
echo "Future potential runs:"
echo "       y0:" ${list_pot_y0_future[@]}
echo "    Begin:" ${list_pot_y1_future[@]}
echo "      End:" ${list_pot_yN_future[@]}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Risk of filling up scratch space if saving too many states.
# Avoid this by splitting run into groups of at most maxNstates states.

# Historical states

# First, get the state(s) that happen during spinup, and split them from states
# in the transient period.
firsthistyear="$(get_param.sh template/${topinsfile} "firsthistyear")"
hist_save_years_spin=""
hist_save_years_trans="${hist_save_years}"
for y in ${hist_save_years}; do
    if [[ ${y} -gt ${firsthistyear} ]]; then
        break
    fi
    hist_save_years_spin="${hist_save_years_spin} ${y}"
    hist_save_years_trans=${hist_save_years_trans/${y}/}
done

# If running spinup period only, make sure to save a restart for firsthistyear
separate_spinup=0
if [[ $(echo ${hist_save_years_spin} | wc -w) -le $((maxNstates - 1)) ]]; then
    separate_spinup=1
    if [[ "$(echo ${hist_save_years_spin} | { grep "${firsthistyear}" || true; })" == "" ]]; then
        hist_save_years_spin="${hist_save_years_spin} ${firsthistyear}"
    fi
fi
# Now split each save_years list up as needed given maxNstates
hist_save_years_lines="$(xargs -n ${maxNstates} <<< ${hist_save_years_spin})"$'\n'"$(xargs -n ${maxNstates} <<< ${hist_save_years_trans})"


# Future states
fut_save_years_lines="$(xargs -n ${maxNstates} <<< ${fut_save_years})"

# Combined
save_years_lines="${hist_save_years_lines}
${fut_save_years_lines}"

#############################################################################################

# Set up function for getting ins files
function get_ins_files {
    if [[ ${do_fu_only} -eq 1 ]]; then
        insfiles="xxx"
    else
        insfiles=$(ls *ins | grep -v "main")
        if [[ ${istest} -eq 1 ]]; then
            insfiles="${realinsfile} ${insfiles}"
        fi
    fi
    echo $insfiles
}

# Set up function for getting absolute state path
function get_state_path {
    if [[ ${thisSSP} != "" ]]; then
        if [[ "${state_path_thisSSP}" == "" ]]; then
            echo "get_state_path(): state_path_thisSSP is unspecified" >&2
            exit 1
        fi
        state_path_absolute="-s ${state_path_thisSSP}"
    fi
    echo "${state_path_absolute}"
}

# Set up function to set up
function do_setup {
    walltime=$1
    ispot=$2
    if [[ "${walltime}" == "" ]]; then
        echo "You must provide walltime to do_setup()"
        exit 1
    fi
    if [[ ${do_fu_only} -eq 1 ]]; then
        gridlist="xxx"
    elif [[ ! -e "${gridlist}" ]]; then
        echo "Gridlist file ${gridlist} not found"
        exit 1
    fi
    if [[ "${state_path}" == "" ]]; then
        echo "Make sure state_path is defined before calling do_setup"
        exit 1
    elif [[ "${state_path}" != "-s "* && "${state_path}" != "--state-path-absolute "* ]]; then
        state_path="-s ${state_path}"
    fi

    lsf_setup_1run.sh ${topinsfile} "$(get_ins_files)" ${gridlist} ${inputmodule} ${nproc} ${arch} ${walltime} -p "${this_prefix}" ${state_path} ${submit} ${ppfudev} ${dependency} ${reservation} --lpjg_topdir $HOME/lpj-guess_git-svn_20190828 ${mem_spec} ${delete_state_arg}

}

pushdq () {
    command pushd "$@" > /dev/null
}

popdq () {
    command popd "$@" > /dev/null
}

function get_latest_run {
    grep "LPJ-GUESS" ${HOME}/submitted_jobs.log | tail -n 1 | sed "s/LPJ-GUESS run: //"
}


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

# Are we actually submitting historical period?
if [[ $(echo ${ssp_list} | cut -f1 -d" ") == "hist" && ${potential_only} -eq 0 ]]; then
    do_hist=1
else
    do_hist=0
fi

# We don't need hist in the SSP list anymore
if [[ ${do_hist} -eq 1 ]]; then
    ssp_list="$(echo ${ssp_list} | sed "s/hist//")"
fi

previous_act_jobnum=
mkdir -p actual
act_restart_year=

# Set up/start a run for each set of save years
while IFS= read -r save_years; do

    # First year in this this determines whether we're in the historical
    # period or not
    first_save_year=$(echo ${save_years} | cut -d" " -f1)
    echo first_save_year $first_save_year

    if [[ ${first_save_year} -le ${hist_yN} ]]; then

        # Sanity check
        if [[ ${do_hist} == 0 ]]; then
            echo "do_hist 0 but save_years ${save_years}"
            exit 1
        fi

        # Set up/submit actual historical run(s)
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

        # Set up/submit potential historical run(s)
        thisSSP="hist"
        . lsf_setup_potential_loop.sh

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
