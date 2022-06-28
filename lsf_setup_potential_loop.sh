#!/bin/bash
set -e


###################
# Process input arguments
###################


#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="lsf_setup_potential_loop.sh"
#Declare the number of mandatory args
margs=3

# Common functions - BEGIN
function example {
echo -e "example: $script ssp126 2015 2089\n"
}

function usage {
echo " "
echo -e "usage: $script \$thisSSP \$future_y1 \$future_yN\n"
}

function help {
usage
echo -e "OPTIONAL:"
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

# SSR: Process positional arguments
# Which SSP?
if [[ "$1" == "" ]]; then
    echo "lsf_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
    exit 1
fi
thisSSP=$1
shift
# Years of the future period
if [[ "$1" == "" ]]; then
    echo "lsf_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
    exit 1
fi
future_y1=$1
shift
if [[ "$1" == "" ]]; then
    echo "lsf_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
    exit 1
fi
future_yN=$1
shift


# Set default values for non-positional arguments
# (none)

while [ "$1" != "" ];
do
   case $1 in
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

# How many years are we discarding at the beginning of the potential run?
if [[ ${Nyears_getready} == "" ]]; then
    Nyears_getready=5
fi
# How many years are we averaging over at the end of the potential run?
if [[ ${Nyears_pot} == "" ]]; then
    Nyears_pot=5
fi


###################
# Setup
###################

# How long is each potential yield run?
Nyears=$((Nyears_getready + Nyears_pot))

# Get list of beginning years
if [[ "${thisSSP}" == "hist" ]]; then
    y1_list=(${list_pot_y1_hist[@]})
    yN_list=(${list_pot_yN_hist[@]})
else
    y1_list=(${list_pot_y1_future[@]})
    yN_list=(${list_pot_yN_future[@]})
fi

###################
# Loop through periods
###################

if [[ "${topinsfile}" != "" && "${inputmodule}" != "" && "${nproc}" != "" && "${arch}" != "" && "${prefix}" != "" ]]; then
    actually_setup=1
else
#    echo topinsfile $topinsfile
#    echo inputmodule $inputmodule
#    echo nproc $nproc
#    echo arch $arch
#    echo prefix $prefix
    actually_setup=0
fi
i=-1
for y1 in ${y1_list[@]}; do
    i=$((i+1))

    is_resuming=0
    restart_year=${y1}
    y0=${y1}
    save_state=${list_pot_save_state[i]}
    if [[ ${thisSSP} != "hist" ]]; then
        is_resuming=${list_future_is_resuming[i]}
        if [[ ${is_resuming} -eq 1 ]]; then
            y0=${list_pot_y0_future[i]}
            restart_year=${future_y1}
        fi
    fi

    # Does this run include the ssp period?
    yN=${yN_list[i]}
    if [[ ${yN} -gt  ${hist_yN} ]]; then
        incl_future=1
    else
        incl_future=0
    fi
    if [[ ${incl_future} -eq 1 && ${thisSSP} == "hist" ]]; then
        echo ${y1}-${yN}: '${incl_future} -eq 1 && ${thisSSP} == "hist"'
        exit 1
    elif [[ ${incl_future} -eq 0 && ${thisSSP} != "hist" ]]; then
        echo ${y1}-${yN}: '${incl_future} -eq 0 && ${thisSSP} != "hist"'
        exit 1
    fi

    # Name this one (e.g. 1850pot)
    first_plut_year=$((y1+Nyears_getready))
    if [[ ${is_resuming} -eq 1 ]]; then
        thisPot=$((y0 + Nyears_getready))pot
    else
        thisPot=${first_plut_year}pot
    fi

    # Get walltime
    if [[ ${istest} -eq 1 ]]; then
        walltime_pot=30
    else
        Nyears=$((yN - y1 + 1))
        walltime_pot=$(echo "$Nyears * $walltime_pot_minutes_peryr" | bc)
        walltime_pot=$(echo "($walltime_pot/$round_walltime_to_next+1)*$round_walltime_to_next" | bc)
        if [[ ${walltime_pot} -lt ${walltime_pot_minutes_minimum} ]]; then
            walltime_pot=${walltime_pot_minutes_minimum}
        elif [[ ${walltime_pot} -gt ${walltime_minutes_max} ]]; then
            echo "Warning: Requested walltime of ${walltime_pot} minutes (${Nyears} yr, ${walltime_pot_minutes_peryr} min/yr, rounding up to next ${round_walltime_to_next}) exceeds maximum ${walltime_minutes_max} minutes. Setting to ${walltime_minutes_max}."
            walltime_pot=${walltime_minutes_max}
        fi
    fi

    # Set up state directory for this run
    if [[ ${do_fu_only} -eq 0 ]]; then
        # Get state directory
        state_path=""
        rundir_top=placeholderneededinlsf_get_state_path_thisSSPdotsh
        cd ..
        state_path_absolute=${runset_workdir}
        if [[ ${istest} -eq 1 ]]; then
            state_path_absolute="${state_path_absolute}_test"
        fi
        if [[ ${is_resuming} -eq 0 && ${y1} -gt ${hist_yN} ]]; then
            state_path_absolute=${state_path_absolute}/actual/states
            state_path_thisSSP="${state_path_absolute}_${thisSSP}"
            . lsf_setup_statedir.sh
        else
            state_path_absolute=${state_path_absolute}/potential/states
            state_path_thisSSP=${state_path_absolute}_${thisPot}
            . lsf_setup_statedir_pot.sh
        fi
        cd potential
    fi

    # Get dirname
    thisdir=${thisPot}_${y1}-${yN}
    if [[ ${incl_future} -eq 1 ]]; then
        mkdir -p "${thisSSP}"
        thisdir="${thisSSP}/${thisdir}"
    else
        mkdir -p "hist"
        thisdir="hist/${thisdir}"
    fi

    # Get jobname
    this_jobname="${thisPot}-${thisSSP}"

#    echo $thisdir
#    echo $state_path_thisSSP
#    echo $restart_year
#    echo $this_jobname
#    continue

    if [[ ${actually_setup} -eq 0 ]]; then
        echo "${thisdir}..."
    else
        echo " "
        echo " "
        echo "${thisdir}..."
        echo " "
    fi

    if [[ ${do_fu_only} -eq 0 ]]; then

        # Archive existing directory, if needed
        if [[ -d "${thisdir}" ]]; then
            this_archive="${thisdir}.$(date "+%Y-%m-%d-%H%M%S").tar"
#            echo "Archiving existing $(pwd)/${thisdir} as ${this_archive}"
            tar -cf "${this_archive}" "${thisdir}"
            rm -rf "${thisdir}"
        fi
    
        # Copy template runDir
        cp -a ../template "${thisdir}"
    
        pushdq "${thisdir}"
    
        # Fill template runDir
        sed -i "s/UUUU/${yN}/" main.ins    # lasthistyear
        # restarting
        sed -i "s/^\!restart_year VVVV/restart_year ${restart_year}/g" main.ins
        sed -i "s/VVVV/${restart_year}/" main.ins
        sed -i "s/firstoutyear 1850/firstoutyear ${y1}/" main.ins    # firstoutyear
        sed -i "s/restart 0/restart 1/g" main.ins
        # saving state
        sed -i "s/WWWW/\"${future_y1}\"/" main.ins    # save_years
        if [[ ${y1} -ge ${future_y1} ]]; then
            sed -i "s/save_state 1/save_state 0/g" main.ins
        fi
        # land use file
        sed -i "s/XXXX/${y0}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -i "s/YYYY/$((y0 + 1))/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        # outputs
        sed -i "s/do_plut 0/do_plut 1/g" landcover.ins
        sed -i "s/ZZZZ/${first_plut_year}/" landcover.ins    # first_plut_year
        # inputs
        if [[ "${thisSSP}" == "hist" ]]; then
            sed -i "s/ssp585/historical/g" main.ins
        else
            sed -i "s/ssp585/${thisSSP}/g" main.ins
        fi
        if [[ "${thisSSP}" == "hist" ]]; then
            sed -i "s/co2_histhistorical/co2_histssp585/g" main.ins
        fi
    
        # Get gridlist for later
        if [[ "${gridlist}" == "" ]]; then
            gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
        fi

        # Set up dependency (or not)
        dependency="${dependency_in}"
        r=-1
        if [[ ${is_resuming} -eq 1 ]]; then
            dep_jobname_prefix="${thisPot}-hist"
        else
            dep_jobname_prefix="act-${thisSSP}"
        fi
        if [[ "${submit}" != "" ]]; then
            for dep_jobnum in ${arr_job_num[@]}; do
                r=$((r+1))
                dep_jobname=${arr_job_name[r]}
                if [[ ${is_resuming} -eq 1 && ${dep_jobname} == "${dep_jobname_prefix}"* ]]; then
                    dependency+=" -d ${dep_jobnum} --dependency-name ${dep_jobname}"
                elif [[ ${is_resuming} -eq 0 ]]; then
                    dep_jobname=${arr_job_name[r]}
                    dep_yN=${arr_yN[r]}
                    if [[ ${dep_jobname} == "${dep_jobname_prefix}"* && ${dep_yN} -ge $((y1 - 1)) ]]; then
                        dependency+=" -d ${dep_jobnum} --dependency-name ${dep_jobname}"
                        break
                    fi
                fi
            done
        else # not submitting
            for dep_jobname in ${arr_job_name[@]}; do
                r=$((r+1))
                if [[ ${is_resuming} -eq 1 && ${dep_jobname} == "${dep_jobname_prefix}"* ]]; then
                    echo "If submitting, would depend on job ${dep_jobname}"
                    break
                elif [[ ${is_resuming} -eq 0 ]]; then
                    dep_yN=${arr_yN[r]}
                    if [[ ${dep_jobname} == "${dep_jobname_prefix}"* && ${dep_yN} -ge $((y1 - 1)) ]]; then
                        echo "If submitting, would depend on job ${dep_jobname}"
                        break
                    fi
                fi
            done
        fi

    else # do_fu_only

        made_home_dir=0
        if [[ ! -d ${thisdir} ]]; then
            made_home_dir=1
            mkdir ${thisdir}
            home_dir_realpath="$(realpath ${thisdir})"
        fi
        pushdq ${thisdir}
    fi

    # Copy over template script
    postproc_template="$HOME/scripts/lsf_postproc.template.sh"
    if [[ ! -f ${postproc_template} ]]; then
       echo "postproc_template file not found: ${postproc_template}"
       exit 1
    fi
    cp ${postproc_template} postproc.sh
    # Replace placeholder(s)
    if [[ "${dirForPLUM}" == "" ]]; then
        echo "dirForPLUM unspecified"
        exit 1
    fi
    sed -i "s@DIRFORPLUM@${dirForPLUM}@g" postproc.sh

    # Actually set up and even submit, if being called from within setup_all.sh
    if [[ ${actually_setup} -eq 1 ]]; then
        if [[ ${yN} -le ${hist_yN} ]]; then
            this_prefix="${prefix}_hist"
        else
            this_prefix="${prefix}_${thisSSP}"
        fi
        ispot=1
        do_setup ${walltime_pot} ${ispot}
    fi

    if [[ ${do_fu_only} -eq 0 ]]; then
        arr_job_name+=("${this_jobname}")
        if [[ "${submit}" != "" ]]; then
            arr_job_num+=($(get_latest_run))
        fi
        arr_y1+=(${y1})
        arr_yN+=(${yN})
    elif [[ ${made_home_dir} -eq 1 ]]; then
        rm "${home_dir_realpath}/postproc.sh"
        rmdir "${home_dir_realpath}"
    fi

    popd 1>/dev/null

done
