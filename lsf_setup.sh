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
walltime_pot="48:00:00"  # Should take around ??? hours
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
arg_do_fu=0
submit=""
dirForPLUM=""
dependency=""
actual_only=0
potential_only=0
nproc=160
ssp_list="hist ssp126 ssp370 ssp585"
Nyears_pot=99999
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
    maxNstates=999
else
    topinsfile=${realinsfile}
    if [[ $do_fu -eq 0 ]]; then
        ppfudev="--no_fu"
    fi
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
yN=$((y1 + Nyears_pot - 1))
while [[ ${y1} -le ${pot_yN} ]] && [[ ${yN} -lt ${future_y1} ]]; do
    if [[ ${y1} -eq ${first_LUyear_past} ]]; then
        list_pot_y1_hist="${y1}"
    else
        list_pot_y1_hist="${list_pot_y1_hist} ${y1}"
    fi
    y1=$((y1 + pot_step))
    yN=$((yN + pot_step))
done

# Generate list of states to save: ssp period
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_yN} ]]; do
    if [[ "${list_pot_y1_future}" == "" ]]; then
        list_pot_y1_future="${y1}"
    else
        list_pot_y1_future="${list_pot_y1_future} ${y1}"
    fi
    y1=$((y1 + pot_step))
done

hist_save_years="${list_pot_y1_hist}"
added_future_y1=0
for y in ${list_pot_y1_future}; do
    if [[ ${y} -gt ${future_y1} && ${added_future_y1} -eq 0 ]]; then
        hist_save_years="${hist_save_years} ${future_y1}"
    fi
    if [[ $((y - 1)) -gt ${hist_yN} ]]; then
        break
    fi
    hist_save_years="${hist_save_years} ${y}"
done

fut_save_years=""
for y in ${list_pot_y1_future}; do
    if [[ ${y} -le ${future_y1} ]]; then
        continue
    fi
    fut_save_years="${fut_save_years} ${y}"
done

echo list_pot_y1_hist $list_pot_y1_hist
echo list_pot_y1_future $list_pot_y1_future
echo hist_save_years $hist_save_years
echo fut_save_years $fut_save_years

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
    if [[ ! -e "${gridlist}" ]]; then
        echo "Gridlist file ${gridlist} not found"
        exit 1
    fi
    if [[ "${state_path}" == "" ]]; then
        state_path=$(get_state_path)
        [[ "${state_path}" == "get_param.sh_FAILED" ]] && exit 1
    fi

    lsf_setup_1run.sh ${topinsfile} "$(get_ins_files)" ${gridlist} ${inputmodule} ${nproc} ${arch} ${walltime} -p "${this_prefix}" ${state_path} ${submit} ${ppfudev} ${dependency} ${reservation} --lpjg_topdir $HOME/lpj-guess_git-svn_20190828 ${mem_spec}
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

# Set up "actual" historical run(s)
thisSSP=""
previous_act_jobnum=
mkdir -p actual
if [[ ${do_hist} -eq 1 ]]; then

    # Risk of filling up scratch space if saving too many states.
    # Avoid this by splitting run into groups of at most maxNstates states.
    #
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

    # Now set up each group of states.
    restart_year=
    while IFS= read -r save_years; do

        # Get lasthistyear
        echo save_years $save_years;
        if [[ "${restart_year}" == "" && ${separate_spinup} -eq 1 ]]; then
            lastsaveyear=${firsthistyear}
        else
            lastsaveyear=$(echo ${save_years} | awk '{print $NF}')
        fi
        lasthistyear=$((lastsaveyear - 1))
        do_break=0
        if [[ ${last_hist_year} -gt ${last_year_act_hist} ]]; then
            echo "Warning: Some historical-period save_year (${lastsaveyear}) implies a run outside historical period (${last_year_act_hist})."
            echo "         Ignoring, and ending historical run(s) in ${last_year_act_hist}."
            lasthistyear=$((last_year_act_hist))
        do_break=1
        fi

        # Set up directory
        if [[ "${restart_year}" == "" ]]; then
            firstyear_thisrun="spin"
        else
            firstyear_thisrun=${restart_year}
        fi
        theseYears="${firstyear_thisrun}-${lasthistyear}"
        dir_acthist="actual/hist_${theseYears}"

        echo "#############################"
        echo "### ${dir_acthist} ###"
        echo "#############################"
    
        # Archive existing directory, if needed
        if [[ -d "${dir_acthist}" ]]; then
            archive_acthist="${dir_acthist}.$(date "+%Y-%m-%d-%H%M%S").tar"
            echo "Archiving existing $(pwd)/${dir_acthist} as ${archive_acthist}"
            tar -cf "${archive_acthist}" "${dir_acthist}"
            rm -rf "${dir_acthist}"
        fi
    
        # Make run directory from template
        cp -a template "${dir_acthist}"
        pushdq ${dir_acthist}
    
        # Replace placeholder values from template
        sed -i "s/UUUU/${lasthistyear}/" main.ins    # lasthistyear
        if [[ "${restart_year}" == "" ]]; then
            sed -iE "s/^\s*restart_year/\!restart_year/g" main.ins
        else
            sed -iE "s/^\!restart_year VVVV/restart_year ${restart_year}/g" main.ins
            sed -i "s/VVVV/${restart_year}/" main.ins    # restart_year
            sed -i "s/restart 0/restart 1/g" main.ins
        fi
        sed -i "s/WWWW/\"${save_years}\"/" main.ins    # save_years
        sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -iE "s/^\s*first_plut_year/\!first_plut_year/g" landcover.ins
        sed -i "s/co2_ssp585_annual_2015_2100.txt/co2_historical_annual_1850_2014.txt/g" main.ins
        sed -i "s/population-density_3b_2015soc_30arcmin_annual_1601_2100.lpjg.nc/population-density_3b_histsoc_30arcmin_annual_1850_2014.lpjg.nc/g" main.ins
        sed -i "s/Effectively 2015soc/histsoc/g" main.ins
        sed -i "s/2015soc/histsoc/g" main.ins
    
        set " "
        
        # Get gridlist
        gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
        [[ "${gridlist}" == "get_param.sh_FAILED" ]] && exit 1
        if [[ "${gridlist}" == "" ]]; then
            echo "Unable to parse gridlist from ${topinsfile} and its dependencies"
            exit 1
        fi
        
        # Set up rundir_top
        rundir_top=$(lsf_get_rundir_top.sh ${istest} 0)
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

        # Set up dependency, if any
        dependency=
        if [[ ${previous_act_jobnum} != "" ]]; then
            dependency="-d ${previous_act_jobnum}"
        fi
        
        # Submit historical run
        state_path=""
        this_prefix="${prefix}_hist"
        ispot=0
        do_setup ${walltime_hist} ${ispot}
    
        arr_job_name+=("act-hist_${theseYears}")
        previous_act_jobnum=$(get_latest_run)
        if [[ "${submit}" != "" ]]; then
            arr_job_num+=( ${previous_act_jobnum} )
        fi
        arr_y1+=(0) # nonsense
        arr_yN+=(${lasthistyear})

        # Set up for next historical run, if any
        restart_year=${lastsaveyear}
    
        echo " "
        echo " "
        popdq

        if [[ ${do_break} -eq 1 ]]; then
            break
        fi
    done <<< ${hist_save_years_lines}
fi

# Get list of years being state-saved from historical run
if [[ "${hist_save_years}" == "" ]]; then
    echo "Error getting save_years from hist run"
    exit 1
fi

# If we're not doing any potential runs...
if [[ ${actual_only} -eq 1 ]]; then
    # If the only period was hist, we're done
    if [[ "${ssp_list}" == "hist" ]]; then
        ssp_list=""

    # Otherwise, if first period was hist, remove it
    else
        ssp_list="${ssp_list/hist /}"
    fi
fi


# Set up SSP actual and potential runs
for thisSSP in ${ssp_list}; do
    if [[ "${thisSSP}" != "hist" && "${thisSSP:0:3}" != "ssp" ]]; then
        thisSSP="ssp${thisSSP}"
    fi
    this_prefix="${prefix}_${thisSSP}"

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

    if [[ ${potential_only} -eq 0 && ${do_future_act} -eq 1 && ${thisSSP} != "hist" ]]; then

        # Risk of filling up scratch space if saving too many states.
        # Avoid this by splitting run into groups of at most maxNstates states.
        fut_save_years_lines="$(xargs -n ${maxNstates} <<< ${fut_save_years})"

        # Now set up each group of states.
        pushdq "actual"
        while IFS= read -r save_years; do

            # Get lasthistyear
            echo save_years $save_years;
            lastsaveyear=$(echo ${save_years} | awk '{print $NF}')
            lasthistyear=$((lastsaveyear - 1))
            do_break=0
            if [[ ${last_hist_year} -gt ${last_year_act_future} ]]; then
                echo "Warning: Some future-period save_year (${lastsaveyear}) implies a run outside future period (${last_year_act_future})."
                echo "         Ignoring, and ending future run(s) in ${last_year_act_future}."
                lasthistyear=$((last_year_act_future))
                do_break=1
            fi

            theseYears="${restart_year}-${lasthistyear}"
            thisDir="${thisSSP}_${theseYears}"
            echo "###############################"
            echo "### actual/${thisDir} ###"
            echo "###############################"
    
            # Archive existing directory, if needed
            if [[ -d "${thisDir}" ]]; then
                archive_thisDir="${thisDir}.$(date "+%Y-%m-%d-%H%M%S").tar"
                echo "Archiving existing $(pwd)/${thisDir} as ${archive_thisDir}"
                tar -cf "${archive_thisDir}" "${thisDir}"
                rm -rf "${thisDir}"
            fi
    
            # Copy and fill template runDir
            echo pwd $(pwd)
            cp -a ../template "${thisDir}"
            cd "${thisDir}"
            sed -i "s/UUUU/${lasthistyear}/" main.ins    # lasthistyear
            sed -iE "s/^\!restart_year VVVV/restart_year ${restart_year}/g" main.ins
            sed -i "s/VVVV/${restart_year}/" main.ins    # restart_year
            sed -i "s/WWWW/\"${list_pot_y1_future}\"/" main.ins    # save_years
            sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
            sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
            sed -iE "s/^\s*first_plut_year/\!first_plut_year/g" landcover.ins
            sed -i "s/restart 0/restart 1/g" main.ins
            sed -i "s/ssp585/${thisSSP}/g" main.ins

            set " "
        
            # Set up state directory for this SSP, if needed
            ispot=0
            . lsf_get_state_path_thisSSP.sh

            # Set up dependency, if any
            dependency=
            if [[ ${previous_act_jobnum} != "" ]]; then
                dependency="-d ${previous_act_jobnum}"
            fi
        
            # Set up run
            ispot=0
            do_setup ${walltime_fut} ${ispot}
        
            # Add run to job list
            arr_job_name+=("act-${thisSSP}_${theseYears}")
            previous_act_jobnum=$(get_latest_run)
            if [[ "${submit}" != "" ]]; then
                arr_job_num+=( ${previous_act_jobnum} )
            fi
            arr_y1+=(${future_y1})
            arr_yN+=($(echo $theseYears | cut -d"-" -f2))
        
            cd ..

            # Set up for next actual run, if needed
            restart_year=${lastsaveyear}
    
        done <<< ${fut_save_years_lines}
        popdq
    fi # If doing future hist

    if [[ ${actual_only} -eq 0 ]]; then
        echo "#########################"
        echo "### potential/${thisSSP} ###"
        echo "#########################"
        set " "
    
        runset_workdir=$(pwd | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
        mkdir -p potential
        cd potential
        save_years=""

        # Set up dirForPLUM
        if [[ "${dirForPLUM}" == "" ]]; then
            dirForPLUM=${runset_workdir}/outputs/outForPLUM-$(date "+%Y-%m-%d-%H%M%S")
            mkdir -p ${dirForPLUM}
            echo "Top-level output directory: $dirForPLUM"
            echo " "
        fi

        . lsf_setup_potential_loop.sh ${thisSSP} ${future_y1} ${future_yN}
        echo " "
        echo " "
        cd ..
    else
        save_years=""
    fi

    echo arr_job_name ${arr_job_name[@]}
    echo arr_job_num ${arr_job_num[@]}
    echo arr_y1 ${arr_y1[@]}
    echo arr_yN ${arr_yN[@]}

done # Loop through SSPs

squeue -o "%10i %.7P %.35j %.10T %.10M %.9l %.6D %.16R %E" -S JOBID | sed "s/unfulfilled/unf/g"

exit 0
