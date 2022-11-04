if [[ "${act_restart_year}" == "" && ${separate_spinup} -eq 1 ]]; then
    lastsaveyear=${firsthistyear}
else
    lastsaveyear=$(echo ${save_years} | awk '{print $NF}')
fi

# Possibly skip this run
if [[ ( "${act_restart_year}" == "" && ${first_act_y1} -gt ${hist_y1} ) || ( "${act_restart_year}" != "" && ${act_restart_year} -lt ${first_act_y1} ) ]]; then
    # Set up for next historical run or finishup, if any
    act_restart_year=${lastsaveyear}
    continue
fi

# Get lasthistyear
echo save_years $save_years;
lasthistyear=$((lastsaveyear - 1))
firstsaveyear=$(echo ${save_years} | cut -d" " -f1)
do_break=0
if [[ ${last_hist_year} -gt ${last_year_act_hist} ]]; then
    echo "Warning: Some historical-period save_year (${lastsaveyear}) implies a run outside historical period (${last_year_act_hist})."
    echo "         Ignoring, and ending historical run(s) in ${last_year_act_hist}."
    lasthistyear=$((last_year_act_hist))
do_break=1
fi

# Set up directory
if [[ "${act_restart_year}" == "" ]]; then
    firstyear_thisrun="spin"
else
    firstyear_thisrun=${act_restart_year}
fi
theseYears="${firstyear_thisrun}-${lasthistyear}"
dir_acthist="actual/hist_${theseYears}"

echo "#############################"
echo "### ${dir_acthist} ###"
echo "#############################"

if [[ ${do_fu_only} -eq 1 ]]; then

    made_home_dir=0
    if [[ ! -d ${dir_acthist} ]]; then
        made_home_dir=1
        mkdir ${dir_acthist}
        home_dir_realpath="$(realpath ${dir_acthist})"
    fi
    pushdq ${dir_acthist}

else

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
    if compgen -G .*.swp > /dev/null; then
        rm .*.swp
    fi

    # Replace placeholder values from template
    sed -i "s/UUUU/${lasthistyear}/" main.ins    # lasthistyear
    if [[ "${act_restart_year}" == "" ]]; then
        sed -iE "s/^\s*restart_year/\!restart_year/g" main.ins
    else
        sed -iE "s/^\!restart_year VVVV/restart_year ${act_restart_year}/g" main.ins
        sed -i "s/VVVV/${act_restart_year}/" main.ins    # restart_year
        sed -i "s/restart 0/restart 1/g" main.ins
    fi
    sed -i "s/WWWW/\"${save_years}\"/" main.ins    # save_years
    if [[ ${runtype} == "lsf" ]]; then
        sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
        sed -iE "s/^\s*first_plut_year/\!first_plut_year/g" landcover.ins
        sed -i "s/co2_ssp585_annual_2015_2100.txt/co2_historical_annual_1850_2014.txt/g" main.ins
        sed -i "s/population-density_3b_2015soc_30arcmin_annual_1601_2100.lpjg.nc/population-density_3b_histsoc_30arcmin_annual_1850_2014.lpjg.nc/g" main.ins
        sed -i "s/Effectively 2015soc/histsoc/g" main.ins
        sed -i "s/2015soc/histsoc/g" main.ins
#    elif [[ ${runtype} == "lsa" ]]; then
    fi

    set " " 

    
    # Get gridlist
    gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
    [[ "${gridlist}" == "get_param.sh_FAILED" ]] && exit 1
    if [[ "${gridlist}" == "" ]]; then
        echo "Unable to parse gridlist from ${topinsfile} and its dependencies"
        exit 1
    fi

fi # if do_fu_only else

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

# Delete restart files?
if [[ ${act_restart_year} -le ${hist_y1} || ${act_restart_year} -eq ${future_y1} ]]; then
    delete_state_arg=
else
    delete_state_arg="--delete-state-year ${act_restart_year}"
    if [[ "${latest_pot_jobnum}" != "" ]]; then
        echo "WILL DELETE ${act_restart_year} STATE IF POTENTIAL JOB ${latest_pot_jobnum} FINISHED OK"
        delete_state_arg+=" --delete-state-year-if-thisjob-ok ${latest_pot_jobnum}"
    else
        echo "WILL DELETE ${act_restart_year} STATE"
    fi
fi

# Submit historical run or finishup
state_path="$(cd ..; lsf_get_rundir_top.sh ${istest} 0)/states"
this_prefix="${prefix}_hist"
ispot=0
do_setup ${walltime_hist} ${ispot} ${delete_state_arg}

if [[ ${do_fu_only} -eq 0 ]]; then
    arr_job_name+=("act-hist_${theseYears}")
    previous_act_jobnum=$(get_latest_run)
    if [[ "${submit}" != "" ]]; then
        arr_job_num+=( ${previous_act_jobnum} )
    fi
    arr_y1+=(0) # nonsense
    arr_yN+=(${lasthistyear})
elif [[ ${made_home_dir} -eq 1 ]]; then
    rmdir "${home_dir_realpath}"
fi

# Set up for next historical run or finishup, if any
act_restart_year=${lastsaveyear}

echo " "
echo " "
popdq

if [[ ${do_break} -eq 1 ]]; then
    break
fi

