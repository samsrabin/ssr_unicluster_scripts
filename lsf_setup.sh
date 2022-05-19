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
walltime_hist="72:00:00"
walltime_fut="6:00:00"  # Should take around 4 hours
walltime_pot="2:00:00"  # Should take around 1 hour
future_y1=2015
firstPart2yr=9999 # The year that will be the first in the 2nd part of the SSP period
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
arg_do_fu=0
submit=""
dirForPLUM=""
dependency=""
actual_only=0
potential_only=0
nproc=160
ssp_list="hist ssp126 ssp370 ssp585"
Nyears_pot=100
pot_y1=1850
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
            arg_do_fu=1
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
        --y1-pot)  shift
            pot_y1=$1
            ;;
        --yN-pot)  shift
            pot_yN=$1
            ;;
        --step-pot)  shift
            pot_step=$1
            ;;
        -d | --dependency)  shift
            dependency="-d $1"
            dependency_pot="-d $1"
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
do_fu=0
if [[ $istest -eq 0 || $arg_do_fu -eq 1 ]]; then
    do_fu=1
fi

#############################################################################################

# Process test vs. real thing
if [[ ${istest} -eq 1 ]]; then
    topinsfile=${testinsfile}
    walltime_hist="30:00"
    walltime_fut="30:00"
    walltime_pot="30:00"
    nproc=${testnproc}
    ppfudev="--dev"
    if [[ $do_fu -eq 0 ]]; then
        ppfudev="--dev"
    else
        ppfudev="--dev --fu"
    fi
    reservation=""
else
    topinsfile=${realinsfile}
    if [[ $do_fu -eq 0 ]]; then
        ppfudev="--no_fu"
    fi
fi

# Are we actually splitting the ssp period into 2 parts?
split_ssp_period=1
if [[ ${firstPart2yr} -gt ${future_yN} ]]; then
    split_ssp_period=0
fi

# Get info for last XXXXpast_YYYYall_LU.txt
first_LUyear_past=$((pot_y1 - Nyears_getready))
last_LUyear_past=${first_LUyear_past}
last_LUyear_all=$((last_LUyear_past + 1))
y1=$((pot_y1 + pot_step))
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

# Generate list of states to save: Historical period
y1=${first_LUyear_past}
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_y1} ]]; do
    if [[ ${y1} -eq ${first_LUyear_past} ]]; then
        list_pot_y1_hist="${y1}"
    else
        list_pot_y1_hist="${list_pot_y1_hist} ${y1}"
    fi
    y1=$((y1 + pot_step))
done
save_years_hist="${list_pot_y1_hist}"
if [[ ${pot_yN} -gt ${future_y1} ]]; then
    if [[ "${save_years_hist}" == "" ]]; then
        save_years_hist="${future_y1}"
    else
        save_years_hist="${list_pot_y1_hist} ${future_y1}"
    fi
fi

# Generate list of states to save: ssp period
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_yN} ]]; do
    if [[ "${list_pot_y1_future}" == "" ]]; then
        list_pot_y1_future="${y1}"
    else
        list_pot_y1_future="${list_pot_y1_future} ${y1}"
    fi
    y1=$((y1 + pot_step))
done

echo list_pot_y1_hist $list_pot_y1_hist
echo list_pot_y1_future $list_pot_y1_future

#############################################################################################

# Set up function for getting ins files
function get_ins_files {
    insfiles=$(ls *ins | grep -v "main")
    if [[ ${istest} -eq 1 ]]; then
        insfiles="${realinsfile} ${insfiles}"
    fi
    echo $insfiles
}

# Set up function for getting absolute state path
function get_state_path {
    if [[ ${thisSSP} != "" ]]; then
        state_path_absolute="-s ${state_path_thisSSP}"
    fi
    echo "${state_path_absolute}"
}

# Set up function to set up
function do_setup {
    walltime=$1
    if [[ "${walltime}" == "" ]]; then
        echo "You must provide walltime to do_setup()"
        exit 1
    fi
    if [[ ! -e "${gridlist}" ]]; then
        echo "Gridlist file ${gridlist} not found"
        exit 1
    fi
    if [[ "${state_path}" == "" ]]; then
        state_path=$(get_state_path)
        [[ "${state_path}" == "get_param.sh_FAILED" ]] && exit 1
    fi
    #croplist=$(grep "pft" $(ls -tr crop_n_pftlist.*.ins  | tail -n 1) | sed -E 's/pft\s+"([^".]+)"\s*\(/\1/g' | grep -v "ExtraCrop")
    lsf_setup_1run.sh ${topinsfile} "$(get_ins_files)" ${gridlist} ${inputmodule} ${nproc} ${arch} ${walltime} -p "${prefix}" ${state_path} ${submit} ${ppfudev} ${dependency} ${reservation} --lpjg_topdir $HOME/lpj-guess_git-svn_20190828 ${mem_spec}
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

# Are we actually submitting historical period?
if [[ $(echo ${ssp_list} | cut -f1 -d" ") == "hist" && ${potential_only} -eq 0 ]]; then
    do_hist=1
else
    do_hist=0
fi


# Set up "actual" historical run
thisSSP=""
mkdir -p actual
dir_acthist="actual/hist"
if [[ ${do_hist} -eq 1 ]]; then
    echo "###################"
    echo "### actual/hist ###"
    echo "###################"

    # Archive existing directory, if needed
    if [[ -d "${dir_acthist}" ]]; then
        archive_acthist="${dir_acthist}.$(date "+%Y-%m-%d-%H%M%S").tar"
        echo "Archiving existing $(pwd)/${dir_acthist} as ${archive_acthist}"
        tar -cf "${archive_acthist}" "${dir_acthist}"
        rm -rf "${dir_acthist}"
    fi

    # Make run directory from template
    cp -a template "${dir_acthist}"
    pushdq "${dir_acthist}"
    sed -i "s/UUUU/${last_year_act_hist}/" main.ins    # lasthistyear
    sed -iE "s/^\s*restart_year/\!restart_year/g" main.ins
    sed -i "s/WWWW/\"${save_years_hist}\"/" main.ins    # save_years
    sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
    sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
    sed -iE "s/^\s*first_plut_year/\!first_plut_year/g" landcover.ins

    popdq
fi
set " "
pushdq "${dir_acthist}"

# Get gridlist
gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
[[ "${gridlist}" == "get_param.sh_FAILED" ]] && exit 1
if [[ "${gridlist}" == "" ]]; then
    echo "Unable to parse gridlist from ${topinsfile} and its dependencies"
    exit 1
fi

# Set up rundir_top
thisbasename=$(lsf_get_basename.sh)
rundir_top=$(lsf_get_rundir_top.sh ${istest})
if [[ "${rundir_top}" == "" ]]; then
    echo "Error finding rundir_top; exiting."
    exit 1
fi
mkdir -p "${rundir_top}"

# Set up dirForPLUM
if [[ "${dirForPLUM}" == "" ]]; then
    dirForPLUM=$(realpath ${rundir_top}/../..)/outputs/outForPLUM-$(date "+%Y-%m-%d-%H%M%S")
fi
mkdir -p ${dirForPLUM}
echo "Top-level output directory: $dirForPLUM"
echo " "

# Submit historical run (or not)
state_path=""
if [[ ${do_hist} -eq 1 && ${potential_only} -eq 0 ]]; then
    hist_save_years=""
    do_setup ${walltime_hist}

    arr_job_name+=("act-hist")
    if [[ "${submit}" != "" ]]; then
        arr_job_num+=( $(get_latest_run) )
    fi
    arr_y1+=(0) # nonsense
    arr_yN+=(${last_year_act_hist})

    echo " "
    echo " "
fi

# Get list of years being state-saved from historical run
hist_save_years="$(get_param.sh ${topinsfile} save_years)"
if [[ "${hist_save_years}" == "" ]]; then
    echo "Error getting save_years from hist run"
    exit 1
fi

cd ..

# If first period was hist, remove it
ssp_list="${ssp_list/hist /}"


# Set up SSP actual and potential runs
for thisSSP in ${ssp_list}; do
    if [[ "${thisSSP:0:3}" != "ssp" ]]; then
        thisSSP="ssp${thisSSP}"
    fi

    # Set up dependency for actual ssp run
    dependency=""
    if [[ "${submit}" != "" && ${do_hist} -eq 1 ]]; then
        r=-1
        for this_jobname in ${arr_job_name[@]}; do
            r=$((r+1))
            if [[ "${this_jobname}" == "act-hist" ]]; then
                dependency="-d ${arr_job_num[r]} --dependency-name 'act-hist'"
                break
            fi
        done
    fi

    if [[ ${split_ssp_period} -eq 1 ]]; then
        theseYears="${future_y1}-$((firstPart2yr - 1))"
    else
        theseYears="${future_y1}-${future_yN}"
    fi
    thisDir=${thisSSP}_${theseYears}
    if [[ ${potential_only} -eq 0 && ${do_future_act} -eq 1 ]]; then
        echo "###############################"
        echo "### actual/${thisSSP} ${theseYears} ###"
        echo "###############################"

        # Archive existing directory, if needed
        if [[ -d "${thisDir}" ]]; then
            archive_thisDir="${thisDir}.$(date "+%Y-%m-%d-%H%M%S").tar"
            echo "Archiving existing $(pwd)/${thisDir} as ${archive_thisDir}"
            tar -cf "${archive_thisDir}" "${thisDir}"
            rm -rf "${thisDir}"
        fi

        # Copy and fill template runDir
        cp -a ../template "${thisDir}"
        pushdq "${thisDir}"
        sed -i "s/UUUU/${last_year_act_future}/" main.ins    # lasthistyear
        sed -iE "s/^\!restart_year VVVV/restart_year ${future_y1}/g" main.ins
        sed -i "s/VVVV/${future_y1}/" main.ins    # restart_year
        sed -i "s/WWWW/\"${list_pot_y1_future}\"/" main.ins    # save_years
        sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -iE "s/^\s*first_plut_year/\!first_plut_year/g" landcover.ins
        sed -i "s/restart 0/restart 1/g" main.ins
        popdq
    fi
    set " "
    cd ${thisDir}


    # Set up state directory for this SSP
    # IF YOU WIND UP WITH PROBLEMS HERE, CONSIDER USING THIS FUNCTIONALITY
    # BUILT IN TO lsf_setup_1run.sh INSTEAD!
    # I.e., -L flag
    # Would need to ensure that it's ONLY used for first part of future runs (if splitting ssp period).
    state_path=""
    state_path_absolute=$(lsf_get_state_path_absolute.sh "${rundir_top}" "${state_path_absolute}")
    state_path_thisSSP="${state_path_absolute}_${thisSSP}"
    mkdir -p ${state_path_thisSSP}
    pushd ${state_path_thisSSP} 1>/dev/null
    for y in ${hist_save_years}; do
        if [[ -L ${y} ]]; then
            rm -f ${y}
        fi
        ln -s ../states/${y}
    done
    popd 1>/dev/null


    # Set up run
    topdir_prev=$(echo $PWD | sed "s@/${thisDir}@/hist@")
    save_years=$(get_param.sh ${topdir_prev}/${topinsfile} "save_years")
    if [[ "${save_years}" == "get_param.sh_FAILED" ]]; then
        echo "get_param.sh_FAILED"
        exit 1
    fi
    if [[ ${potential_only} -eq 0 ]]; then
        do_setup ${walltime_fut}

        if [[ ${split_ssp_period} -eq 1 ]]; then
            arr_job_name+=("act-${thisSSP}_${theseYears}")
        else
            arr_job_name+=("act-${thisSSP}")
        fi
        if [[ "${submit}" != "" ]]; then
            arr_job_num+=($(get_latest_run))
        fi
        arr_y1+=(${future_y1})
        arr_yN+=($(echo $theseYears | cut -d"-" -f2))
    fi

    cd ..

    if [[ ${split_ssp_period} -eq 1 ]]; then

        theseYears="${firstPart2yr}-$((future_yN - Nyears_pot))"
        if [[ ${potential_only} -eq 0 ]]; then
            echo " "
            echo " "
            echo "###############################"
            echo "### actual/${thisSSP} ${theseYears} ###"
            echo "###############################"
        fi
        set " "
        prevDir=${thisDir}
        thisDir=${thisSSP}_${theseYears}
        cd ${thisDir}

        # Set up run
        topdir_prev=$(echo $PWD | sed "s@/${thisDir}@/${prevDir}@")
        save_years2=$(get_param.sh ${topdir_prev}/${topinsfile} "save_years")
        if [[ "${save_years2}" == "get_param.sh_FAILED" ]]; then
            echo "get_param.sh_FAILED"
            exit 1
        fi
        save_years="${save_years} ${save_years2}"
        if [[ ${potential_only} -eq 0 ]]; then
            do_setup ${walltime_fut}

            arr_job_name+=("act-${thisSSP}_${theseYears}")
            if [[ "${submit}" != "" ]]; then
                arr_job_num+=($(get_latest_run))
            fi
            arr_y1+=(${future_y1})
            arr_yN+=($(echo $theseYears} | cut -d"-" -f2))

            echo " "
            echo " "
        fi
    
        cd ..

    fi # if split_ssp_period

    if [[ ${actual_only} -eq 0 ]]; then
        echo "#########################"
        echo "### potential/${thisSSP} ###"
        echo "#########################"
        set " "
    
        cd ..
        mkdir -p potential
        cd potential
        save_years=""
        state_path=$(echo $state_path | sed -E "s/ -L.*//")
        . lsf_setup_potential_loop.sh ${thisSSP} ${future_y1} ${future_yN}
        echo " "
        echo " "
    else
        save_years=""
    fi
    cd ../actual


    echo arr_job_name ${arr_job_name[@]}
    echo arr_job_num ${arr_job_num[@]}
    echo arr_y1 ${arr_y1[@]}
    echo arr_yN ${arr_yN[@]}

done # Loop through SSPs

squeue -o "%10i %.7P %.35j %.10T %.10M %.9l %.6D %.16R %E" -S JOBID | sed "s/unfulfilled/unf/g"

exit 0