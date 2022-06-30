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
    echo pwd $(pwd)
    cp -a ../template "${thisDir}"
    cd "${thisDir}"
    sed -i "s/UUUU/${lasthistyear}/" main.ins    # lasthistyear
    sed -iE "s/^\!restart_year VVVV/restart_year ${act_restart_year}/g" main.ins
    sed -i "s/VVVV/${act_restart_year}/" main.ins    # restart_year
    sed -i "s/WWWW/\"${fut_save_years}\"/" main.ins    # save_years
    sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
    sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
    sed -iE "s/^\s*first_plut_year/\!first_plut_year/g" landcover.ins
    sed -i "s/restart 0/restart 1/g" main.ins
    sed -i "s/ssp585/${thisSSP}/g" main.ins

    set " "

    # Set up state directory for this SSP, if needed
    state_path_absolute="$(get_equiv_workdir.sh "../..")"
    if [[ ${istest} -eq 1 ]]; then
        state_path_absolute="${state_path_absolute}_test"
    fi
    state_path_absolute=${state_path_absolute}/actual/states
    state_path_thisSSP="${state_path_absolute}_${thisSSP}"
    . lsf_setup_statedir.sh

    ispot=0
    . lsf_get_state_path_thisSSP.sh

    # Set up dependency for next actual run, if any
    dependency="${dependency_in}"
    if [[ ${previous_act_jobnum} != "" ]]; then
        dependency+=" -d ${previous_act_jobnum}"
    fi
fi

# Set up run
ispot=0
delete_state_arg=
do_setup ${walltime_fut} ${ispot}

# Set up dirForPLUM
if [[ "${dirForPLUM}" == "" ]]; then
    dirForPLUM=$(realpath ${rundir_top}/../..)/outputs/outForPLUM-$(date "+%Y-%m-%d-%H%M%S")
fi
mkdir -p ${dirForPLUM}
echo "Top-level output directory: $dirForPLUM"
echo " "

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
