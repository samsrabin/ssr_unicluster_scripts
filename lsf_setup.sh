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
Nyears_getready=3

if [[ "${reservation}" == "" ]]; then
    sequential_pot=0
else
    sequential_pot=1
fi

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
        --seq-pot)
            sequential_pot=1
            ;;
        --no-seq-pot)
            sequential_pot=0
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
first_LUyear_past=$((pot_y1 - Nyears_getready + 1))
last_LUyear_past=${first_LUyear_past}
last_LUyear_all=$((last_LUyear_past + 1))
y1=$((pot_y1 + pot_step))
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_y1} ]]; do
    last_LUyear_past=$((last_LUyear_past + pot_step))
    last_LUyear_all=$((last_LUyear_all + pot_step))
    y1=$((y1 + pot_step))
done
hist_yN=$((future_y1 - 1))
last_year_act_hist=$((last_LUyear_past<hist_yN ? last_LUyear_past : hist_yN))

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

    # Generate list of states to save
    y1=${first_LUyear_past}
    while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_y1} ]]; do
        if [[ ${y1} -eq ${first_LUyear_past} ]]; then
            list_pot_y1="${y1}"
        else
            list_pot_y1="${list_pot_y1} ${y1}"
        fi
        y1=$((y1 + pot_step))
    done
    if [[ ${last_year_act_hist} -ge ${future_y1} ]]; then
        if [[ "${list_pot_y1}" == "" ]]; then
            list_pot_y1="${future_y1}"
        else
            list_pot_y1="${list_pot_y1} ${future_y1}"
        fi
    fi

    # Make run directory from template
    cp -a template "${dir_acthist}"
    pushdq "${dir_acthist}"
    sed -i "s/UUUU/${last_year_act_hist}/" main.ins    # lasthistyear
    sed -i "s/VVVV/0/" main.ins    # restart_year
    sed -i "s/WWWW/\"${list_pot_y1}\"/" main.ins    # save_years
    sed -i "s/XXXX/${last_LUyear_past}/" main.ins    # XXXXpast_YYYYall_LU.txt
    sed -i "s/YYYY/${last_LUyear_all}/" main.ins    # XXXXpast_YYYYall_LU.txt
    sed -i "s/ZZZZ/0/" landcover.ins    # first_plut_year

    popdq
fi
set " "
pushdq "${dir_acthist}"



echo "INCOMPLETE. EXITING."
exit 1



# Get gridlist
gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
[[ "${gridlist}" == "get_param.sh_FAILED" ]] && exit 1
if [[ "${gridlist}" == "" ]]; then
    echo "Unable to parse gridlist from ${topinsfile} and its dependencies"
    exit 1
fi

## Set up postprocessing
#outy1=$((firstpotyear + Nyears_getready))
## Copy over template script
#postproc_template="$HOME/scripts/lsf_postproc.template.sh"
#if [[ ! -f ${postproc_template} ]]; then
#    echo "postproc_template file not found: ${postproc_template}"
#    exit 1
#fi
#cp ${postproc_template} postproc.sh
## Replace years
#sed -i "s/OUTY1/${outy1}/g" postproc.sh
#sed -i "s/OUTYN/$((future_y1 - 1))/g" postproc.sh
#sed -i "s/NYEARS_POT/${Nyears_pot}/g" postproc.sh
#sed -i "s/THISSSP/hist/g" postproc.sh
## Set up top-level output directory
#workdir=$WORK
#if [[ "${workdir}" == "" ]]; then
#    echo "\$WORK undefined"
#    exit 1
#elif [[ ! -e "${workdir}" ]]; then
#    echo "\$WORK not found: $WORK"
#    exit 1
#fi
#echo " "
#
## Set up dirForPLUM
#thisbasename=$(lsf_get_basename.sh)
#rundir_top=$(lsf_get_rundir_top.sh ${istest})
#if [[ "${rundir_top}" == "" ]]; then
#    echo "Error finding rundir_top; exiting."
#    exit 1
#fi
#mkdir -p "${rundir_top}"
#if [[ "${dirForPLUM}" == "" ]]; then
#    dirForPLUM=$(realpath ${rundir_top}/../..)/outputs/outForPLUM-$(date "+%Y-%m-%d-%H%M%S")
#fi
#mkdir -p ${dirForPLUM}
#echo "Top-level output directory: $dirForPLUM"
#echo " "

# Submit historical run (or not)
state_path=""
if [[ ${do_hist} -eq 1 && ${potential_only} -eq 0 ]]; then
    hist_save_years=""
    do_setup ${walltime_hist}
    echo " "
    echo " "
fi

# Get list of years being state-saved from historical run
hist_save_years="$(get_param.sh ${topinsfile} save_years)"
if [[ "${hist_save_years}" == "" ]]; then
    echo "Error getting save_years from hist run"
    exit 1
fi



echo "hist_save_years: ${hist_save_years}"
exit 1





cd ..

# If first period was hist, remove it
if [[ ${do_hist} -eq 1 ]]; then
    ssp_list="${ssp_list/hist /}"
fi


# Set up SSP actual and potential runs
for thisSSP in ${ssp_list}; do
    if [[ "${thisSSP:0:3}" != "ssp" ]]; then
        thisSSP="ssp${thisSSP}"
    fi

    # Actual runs always wait for previous hist or SSP run to complete
    dependency="-d LATEST"

    if [[ ${split_ssp_period} -eq 1 ]]; then
        theseYears="${future_y1}-$((firstPart2yr - 1))"
    else
        theseYears="${future_y1}-${future_yN}"
    fi
    thisDir=${thisSSP}_${theseYears}
    if [[ ! -d ${thisDir} ]]; then
        echo "Skipping ${thisSSP} because ${thisDir} does not exist"
        continue
    fi
    if [[ ${potential_only} -eq 0 ]]; then
        echo "###############################"
        echo "### actual/${thisSSP} ${theseYears} ###"
        echo "###############################"
    fi
    set " "
    cd ${thisDir}
    # Copy over template script
    postproc_template="$HOME/scripts/lsf_postproc.template.sh"
    if [[ ! -f ${postproc_template} ]]; then
        echo "postproc_template file not found: ${postproc_template}"
        exit 1
    fi
    cp ${postproc_template} postproc.sh
    # Replace years
    while [[ ${outy1} -lt ${future_y1} ]]; do
        outy1=$((outy1 + Nyears_pot))
    done
    sed -i "s/OUTY1/${outy1}/g" postproc.sh
    sed -i "s/OUTYN/$((firstPart2yr - 1))/g" postproc.sh
    sed -i "s/NYEARS_POT/${Nyears_pot}/g" postproc.sh
    sed -i "s/THISSSP/${thisSSP}/g" postproc.sh


    # Set up state directory for this SSP
    # IF YOU WIND UP WITH PROBLEMS HERE, CONSIDER USING THIS FUNCTIONALITY
    # BUILT IN TO lsf_setup_1run.sh INSTEAD!
    # I.e., -L flag
    # Would need to ensure that it's ONLY used for first part of future runs.
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
        # Copy over template script
        postproc_template="$HOME/scripts/lsf_postproc.template.sh"
        if [[ ! -f ${postproc_template} ]]; then
            echo "postproc_template file not found: ${postproc_template}"
            exit 1
        fi
        cp ${postproc_template} postproc.sh
        # Replace years
        while [[ ${outy1} -lt ${firstPart2yr} ]]; do
            outy1=$((outy1 + Nyears_pot))
        done
        sed -i "s/OUTY1/${outy1}/g" postproc.sh
        sed -i "s/OUTYN/$((future_yN - Nyears_pot))/g" postproc.sh
        sed -i "s/NYEARS_POT/${Nyears_pot}/g" postproc.sh
        sed -i "s/THISSSP/${thisSSP}/g" postproc.sh
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
    
        # Set dependency for all potential runs to latest actual run
        if [[ ${sequential_pot} -eq 0 ]]; then
            if [[ ${potential_only} -eq 1 ]]; then
                dependency="${dependency_pot}"
            else
                lastactrun=$(tail ~/submitted_jobs.log | grep "LPJ-GUESS" | tail -n 1 | grep -oE "[0-9]+")
                dependency="-d ${lastactrun}"
            fi
        fi
        cd ../potential
        save_years=""
        state_path=$(echo $state_path | sed -E "s/ -L.*//")
        . lsf_setup_potential_loop.sh ${thisSSP} ${future_y1} ${future_yN}
        echo " "
        echo " "
    else
        save_years=""
    fi
    cd ../actual
done # Loop through SSPs


exit 0
