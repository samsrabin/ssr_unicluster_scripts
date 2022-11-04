if [[ "${act_restart_year}" == "" ]]; then
    act_restart_year=${future_y1}
fi
lastsaveyear=$(echo ${save_years} | awk '{print $NF}')

# Possibly skip this run
if [[ ${act_restart_year} -lt ${first_act_y1} ]]; then
    # Set up for next historical run or finishup, if any
    act_restart_year=${lastsaveyear}
    continue
fi

# Get lasthistyear
echo save_years $save_years;
lasthistyear=$((lastsaveyear - 1))
do_break=0
if [[ ${last_hist_year} -gt ${last_year_act_future} ]]; then
    echo "Warning: Some future-period save_year (${lastsaveyear}) implies a run outside future period (${last_year_act_future})."
    echo "         Ignoring, and ending future run(s) in ${last_year_act_future}."
    lasthistyear=$((last_year_act_future))
    do_break=1
fi

theseYears="${act_restart_year}-${lasthistyear}"
thisDir="${thisSSP}_${theseYears}"
echo "###############################"
echo "### actual/${thisDir} ###"
echo "###############################"

if [[ ${do_fu_only} -eq 1 ]]; then

    made_home_dir=0
    if [[ ! -d ${thisDir} ]]; then
        made_home_dir=1
        mkdir ${thisDir}
        home_dir_realpath="$(realpath ${thisDir})"
    fi
    cd "${thisDir}"

else

    # Archive existing directory, if needed
    if [[ -d "${thisDir}" ]]; then
        archive_thisDir="${thisDir}.$(date "+%Y-%m-%d-%H%M%S").tar"
        echo "Archiving existing $(pwd)/${thisDir} as ${archive_thisDir}"
        tar -cf "${archive_thisDir}" "${thisDir}"
        rm -rf "${thisDir}"
    fi

    # Copy and fill template runDir
    cp -a ../template "${thisDir}"
    cd "${thisDir}"
    sed -i "s/UUUU/${lasthistyear}/" main.ins    # lasthistyear
    sed -i "s/restart 0/restart 1/g" main.ins
    sed -iE "s/^\!restart_year VVVV/restart_year ${act_restart_year}/g" main.ins
    sed -i "s/VVVV/${act_restart_year}/" main.ins    # restart_year
    sed -i "s/WWWW/\"${fut_save_years}\"/" main.ins    # save_years
    if [[ ${runtype} == "lsf" ]]; then
        sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -iE "s/^\s*first_plut_year/\!first_plut_year/g" landcover.ins
        sed -i "s/ssp585/${thisSSP}/g" main.ins
    elif [[ ${runtype} == "sai" ]]; then
        # Need to add functionality to handle ensemble members
        if [[ "${thisSSP}" == "arise1.5" ]]; then
            sed -i "s/CESM CMIP6 historical, ensemble member 1/CESM-WACCM ARISE-1.5, ensemble member 1/g" main.ins
            sed -i "s/timeseries-cmip6/ARISE-SAI-1.5/g" main.ins
            sed -i "s/b.e21.BWHIST.f09_g17.CMIP6-historical-WACCM.001/b.e21.BW.f09_g17.SSP245-TSMLT-GAUSS-DEFAULT.001/g" main.ins
            sed -i "s/18500101-20141231/20350101-20691230/g" main.ins
            sed -i -e "/CESM-WACCM ssp245, ensemble member 1/,+6d" main.ins
        elif [[ "${thisSSP}" != "hist" && "${thisSSP}" != "ssp245" ]]; then
            echo "SSP ${thisSSP} not recognized for runtype ${runtype}" >&2
            exit 1
        fi
    else
        echo "rc_1_actfut.sh doesn't know ins-file substitutions for runtype ${runtype}" >&2
        exit 1
    fi

    # Get gridlist
    gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
    [[ "${gridlist}" == "get_param.sh_FAILED" ]] && exit 1
    if [[ "${gridlist}" == "" ]]; then
        echo "Unable to parse gridlist from ${topinsfile} and its dependencies"
        exit 1
    fi

    set " "

    # Set up state directory for this SSP, if needed
    state_path="$(cd ..; lsf_get_rundir_top.sh ${istest} 0)/states_${thisSSP}"
    state_path_thisSSP="${state_path}"
    . lsf_setup_statedir.sh

    ispot=0
fi

# Delete restart files?
if [[ ${act_restart_year} -le ${hist_y1} || ${act_restart_year} -eq ${future_y1} ]]; then
    delete_state_arg=
else
    echo "WILL DELETE ${act_restart_year} STATE"
    delete_state_arg="--delete-state-year ${act_restart_year}"
fi

# Set up rundir_top
if [[ "${rundir_top}" == "" ]]; then
    rundir_top=$(lsf_get_rundir_top.sh ${istest} 0)
    if [[ "${rundir_top}" == "" ]]; then
        echo "Error finding rundir_top; exiting."
        exit 1
    fi
    if [[ ${do_fu_only} -eq 0 ]]; then
        mkdir -p "${rundir_top}"
    fi
fi

# Set up run
ispot=0
do_setup ${walltime_fut} ${ispot} ${delete_state_arg}

if [[ ${do_fu_only} -eq 0 ]]; then

    # Add run to job list
    arr_job_name+=("act-${thisSSP}_${theseYears}")
    previous_act_jobnum=$(get_latest_run)
    if [[ "${submit}" != "" ]]; then
        arr_job_num+=( ${previous_act_jobnum} )
    fi
    arr_y1+=(${future_y1})
    arr_yN+=($(echo $theseYears | cut -d"-" -f2))

else
    if [[ ${made_home_dir} -eq 1 ]]; then
        rmdir "${home_dir_realpath}"
    fi
fi

cd ..

# Set up for next actual run, if needed
act_restart_year=${lastsaveyear}
