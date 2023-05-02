#!/bin/bash
set -e

echo "#########################"
echo "### potential/${thisSSP} ###"
echo "#########################"
set " "

mkdir -p potential
cd potential


###################
# Setup
###################

# How long is each potential yield run?
Nyears=$((Nyears_getready + Nyears_pot))

# Get list of beginning years
y1_list=()
yN_list=()
if [[ "${thisSSP}" == "${histname}" && ${post2034sai_ssp245} -eq 0 ]]; then
    y1_list=()
    yN_list=()
    if [[ ${thisSSP} == "ssp245"* && ${sai_ssp245_resume2015} -eq 1 ]]; then
        y1_list+=($((hist_y1 - Nyears_getready)))
        yN_list+=($((hist_y1 + Nyears_pot - 1)))
    fi
    y1_list+=(${list_pot_y1_hist[@]})
    yN_list+=(${list_pot_yN_hist[@]})
    echo "y1_list hist: ${y1_list[@]}"
    echo "yN_list hist: ${yN_list[@]}"
else
    y1_list=(${list_pot_y1_future[@]})
    yN_list=(${list_pot_yN_future[@]})
    echo "y1_list future: ${y1_list[@]}"
    echo "yN_list future: ${yN_list[@]}"
fi

did_reset_dependency_potloop=0

###################
# Loop through periods
###################

if [[ "${topinsfile}" != "" && "${inputmodule}" != "" && "${nproc}" != "" && "${arch}" != "" && "${prefix}" != "" ]]; then
    actually_setup=1
else
    actually_setup=0
fi
i=-1
for y1 in ${y1_list[@]}; do
    echo y1 $y1
    i=$((i+1))

    is_resuming=0
    pot_restart_year=${y1}
    y0=${y1}
    save_state=${list_pot_save_state[i]}
    if [[ ${thisSSP} != "${histname}" || ${post2034sai_ssp245} -eq 1 ]]; then
        is_resuming=${list_future_is_resuming[i]}
        if [[ ${is_resuming} -eq 1 ]]; then
            y0=${list_pot_y0_future[i]}
            pot_restart_year=${future_y1}
        fi
    elif [[ ${thisSSP} == "ssp245"* && ${sai_ssp245_resume2015} -eq 1 ]]; then
        is_resuming=1
        y1=$((y0 + Nyears_getready))
        sai_ssp245_resume2015=0
    fi

    # Get jobname
    if [[ ${is_resuming} -eq 1 ]]; then
        first_plut_year=$((y0+Nyears_getready))
    else
        first_plut_year=$((y1+Nyears_getready))
    fi
    thisPot=${first_plut_year}pot
    this_jobname="${thisPot}-${thisSSP}"
    if [[ "${runtype}" == "sai" && "${thisPot}" == "2035pot" && "${thisSSP}" == "ssp245"* ]]; then
        this_jobname+="-${y1}"
    fi

#    echo thisSSP $thisSSP
#    echo save_years $save_years
#    echo pot_years $pot_years
#    echo y0 $y0
#    echo y1 $y1
#    echo first_pot_y1 $first_pot_y1
#    echo first_save_year $first_save_year
#    echo is_resuming $is_resuming
#    echo pot_restart_year $pot_restart_year
#    echo act_restart_year $act_restart_year
#    echo s $s
#    echo "did_resume_pre2015pots ${did_resume_pre2015pots[@]}"


    if [[ ( "${save_years}" != *"${y1}"* || "${pot_years}" != *"${y0}"* ) && ( ( ${first_pot_y1} -ge ${first_save_year} && ${potential_only} -ne 1 ) || ${is_resuming} -eq 0 ) ]]; then
#        echo skipping A
        continue
    elif [[ ${is_resuming} -eq 1 && ${y0} -ge ${first_save_year} ]]; then
#        echo skipping B
        continue
    elif [[ ( ${is_resuming} -eq 1 && ${first_pot_y1} -gt ${y1} ) || ( ${is_resuming} -eq 0 && $((first_pot_y1 - Nyears_getready)) -gt ${y1} ) ]]; then
#        echo skipping C
        continue
    elif [[ ${pot_restart_year} -gt ${act_restart_year} ]]; then
        # This potential run begins after the latest-generated state file
#        echo skipping D
        continue
    elif [[ ${is_resuming} -eq 1 && " ${arr_job_name[@]} " == *" ${this_jobname} "* ]]; then
        # This run is a resumer for its scenario but has already been set up
#        echo skipping E
        continue
    fi

    # Ensure job name uniqueness (won't work if job names contain spaces)
    if [[ " ${arr_job_name[@]} " == *" ${this_jobname} "* ]]; then
        echo "Job ${this_jobname} already present in arr_job_name (${arr_job_name[@]})" >&2
        exit 1
    fi
    echo this_jobname $this_jobname

    # Reset dependency info
    if [[ ${did_reset_dependency_potloop} -eq 0 ]]; then
        # This string will be used for actual runs that we want
        # to make wait until after the completion of this set of
        # potential runs.
        if [[ ${potential_only} -eq 1 ]]; then
            if [[ "${dependency_on_latest_potset}" != "" ]]; then
                dependency="${dependency_on_latest_potset}"
                dependency_on_latest_potset=""
            else
                dependency="${dependency_in}"
            fi
        else
            dependency_on_latest_potset="${dependency_in}"
        fi
        did_reset_dependency_potloop=1
    fi

    # Does this run include the ssp period?
    yN=${yN_list[i]}
    if [[ ${yN} -gt  ${hist_yN} ]]; then
        incl_future=1
    else
        incl_future=0
    fi
    if [[ ${incl_future} -eq 1 && ${thisSSP} == "${histname}" && ${post2034sai_ssp245} -eq 0 ]]; then
        echo ERROR ${y1}-${yN}: '${incl_future} -eq 1 && ${thisSSP} == "${histname}" && ${post2034sai_ssp245} -eq 0'
        exit 1
    elif [[ ${incl_future} -eq 0 && ${thisSSP} != "${histname}" ]]; then
        echo ERROR ${y1}-${yN}: '${incl_future} -eq 0 && ${thisSSP} != "${histname}"'
        exit 1
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

    # Is this run saving state for a special reason?
    save_state_sai2035=0
    if [[ "${runtype}" == "sai" && ${y1} -lt 2035 && ${yN} -ge 2035 ]]; then
        save_state_sai2035=1
    fi
    save_state_special=${save_state_sai2035}

    # Set up state directory for this run
    if [[ ${do_fu_only} -eq 0 ]]; then
        # Get state directory
        state_path=""
        rundir_top=placeholderneededinrc_get_state_path_thisSSPdotsh
        cd ..
        state_path_absolute=${runset_workdir}
        if [[ ${is_resuming} -eq 0 && ${y1} -gt ${hist_yN} && ${save_state_special} -eq 0 ]]; then
            state_path_absolute=${state_path_absolute}/actual/states
            state_path_thisSSP="${state_path_absolute}_${thisSSP}"
            . rc_setup_statedir.sh
        else
            state_path_absolute=${state_path_absolute}/potential/states
            state_path_thisSSP=${state_path_absolute}_${thisPot}
            . rc_setup_statedir_pot.sh
        fi
        state_path="${state_path_thisSSP}"
        cd potential
    fi

    # Get dirname
    thisdir=${thisPot}_${y1}-${yN}
    if [[ ${incl_future} -eq 1 ]]; then
        thisTopDir="${thisSSP}"
    else
        thisTopDir="${histname}"
    fi
    mkdir -p "${thisTopDir}"
    thisdir="${thisTopDir}/${thisdir}"

#    echo $thisdir
#    echo $state_path_thisSSP
#    echo $pot_restart_year
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
        cp -aL ../template "${thisdir}"
    
        pushdq "${thisdir}"
    
        # Fill template runDir
        sed -i "s/UUUU/${yN}/" main.ins    # lasthistyear
        [[ "${isimip3_climate_dir}" ]] && sed -i "s@ISIMIP3CLIMATEDIR@${isimip3_climate_dir}@g" main.ins
        if [[ "${runtype}" != "sai" && "${gcm_long}" ]]; then
            sed -i "s/GCMLONGNAME/${gcm_long}/g" main.ins
            sed -i "s/GCMLONGLOWER/${gcm_long_lower}/g" main.ins
            sed -i "s/ENSEMBLEMEMBER/${ensemble_member}/g" main.ins
        fi
        # restarting
        sed -i "s/^\!restart_year VVVV/restart_year ${pot_restart_year}/g" main.ins
        sed -i "s/VVVV/${pot_restart_year}/" main.ins
        sed -i "s/firstoutyear 1850/firstoutyear ${y1}/" main.ins    # firstoutyear
        sed -i "s/restart 0/restart 1/g" main.ins
        if [[ ${runtype} == "lsf" ]]; then
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
            if [[ "${thisSSP}" == "${histname}" ]]; then
                sed -i "s/ssp585/historical/g" main.ins
            else
                sed -i "s/ssp585/${thisSSP}/g" main.ins
            fi
            if [[ "${thisSSP}" == "${histname}" ]]; then
                sed -i "s/co2_histhistorical/co2_histssp585/g" main.ins
            fi
            # number of patches
            sed -i -E "s/npatch_secondarystand\s+[0-9]+/npatch_secondarystand 20/g" landcover.ins
        elif [[ ${runtype} == "sai" || ${runtype} == "lsa" ]]; then
            if [[ ${runtype} == "sai" ]]; then
                if [[ "${thisSSP}" == "arise1.5"* ]]; then
                    # Special handling because historical period doesn't transition directly to ARISE period. Thus we put ARISE stuff in file_*1...
                    sed -i "s/CESM CMIP6 historical, ensemble member ENSEMBLEMEMBERHIST/CESM-WACCM ARISE-1.5, ensemble member ${ensemble_member_fut}/g" main.ins
                    sed -i "s/timeseries-cmip6/ARISE-SAI-1.5/g" main.ins
                    sed -i "s/b.e21.BWHIST.f09_g17.CMIP6-historical-WACCM.ENSEMBLEMEMBERHIST/b.e21.BW.f09_g17.SSP245-TSMLT-GAUSS-DEFAULT.ENSEMBLEMEMBERFUT/g" main.ins
                    sed -i "s/18500101-20141231/20350101-20691231/g" main.ins
                    # ...and delete file_*2
                    sed -i -e "/CESM-WACCM ssp245, ensemble member/,+6d" main.ins
                elif [[ "${thisSSP}" != "${histname}" && "${thisSSP}" != "ssp245"* ]]; then
                    echo "SSP ${thisSSP} not recognized for runtype ${runtype}" >&2
                    exit 1
                else
                    sed -i "s/historical, ensemble member 1/historical, ensemble member ${ensemble_member_hist}/g" main.ins
                    sed -i "s/ssp245, ensemble member 1/ssp245, ensemble member ${ensemble_member_fut}/g" main.ins
                fi
                sed -i "s/ENSEMBLEMEMBERHIST/${ensemble_member_hist}/g" main.ins
                sed -i "s/ENSEMBLEMEMBERFUT/${ensemble_member_fut}/g" main.ins
            elif [[ ${runtype} == "lsa" ]]; then
                sed -i "s/ssp585/${thisSSP}/g" main.ins
            fi
            do_save_state=0
            save_state_year=${future_y1}
            if [[ ${first_plut_year} -ge ${future_y1} && ${y1} -lt ${future_y1} ]]; then
                do_save_state=1
            elif [[ ${save_state_sai2035} -eq 1 ]]; then
                do_save_state=1
                save_state_year=2035
            fi
            # Save state if this potential run will need to be resumed in a future climate
            sed -i "s/WWWW/\"${save_state_year}\"/g" main.ins
            if [[ ${do_save_state} -eq 0 ]]; then
                sed -i "s/save_state 1/save_state 0/g" main.ins
            fi
            # Set up restart info
            sed -i "s/restart 0/restart 1/g" main.ins
        else
            echo "rc_setup_potential_loop.sh doesn't know ins-file substitutions for runtype ${runtype}" >&2
            exit 1
        fi

        if [[ ${runtype} != "lsf" ]]; then
            # Make LPJ-GUESS use PFT-specific N fertilization instead of input file
            sed -i "s/^param \"file_Nfert\".*/\param \"file_Nfert\" (str \"\")/g" crop.ins
            # Set do_potyield to 1 and remove file_lucrop, which is thus unnecessary.
            sed -i -E 's@param "file_lucrop".*$@param "file_lucrop" (str "")\ndo_potyield 1@g' landcover.ins
        fi

    
        # Get gridlist for later
        if [[ "${gridlist}" == "" ]]; then
            gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
        fi

        # Set up dependency (or not)
        if [[ ${potential_only} -eq 0 ]]; then
            dependency="${dependency_in}"
            r=-1
            if [[ ${is_resuming} -eq 1 ]]; then
                dep_jobname_prefix="${thisPot}-${histname}"
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
            fi # whether submitting
        fi # if not potential_only

    else # do_fu_only

        made_home_dir=0
        if [[ ! -d ${thisdir} ]]; then
            made_home_dir=1
            mkdir ${thisdir}
            home_dir_realpath="$(realpath ${thisdir})"
        fi
        pushdq ${thisdir}
    fi

    # Deal with postproc script
    postproc_template="$HOME/scripts/${runtype}_postproc.template.pot.sh"
    if [[ ${runtype} == "lsa" || ${runtype} == "sai" ]]; then
        cp "${postproc_template}" postproc.sh
        sed -i "s/QQQQ/${first_plut_year}/g" postproc.sh
        sed -i "s/UUUU/${yN}/g" postproc.sh
        sed -i "s/THISSSP/${thisSSP}/g" postproc.sh
        if [[ "${dirForPLUM}" == "" ]]; then
            echo "dirForPLUM unspecified"
            exit 1
        fi
        sed -i "s@DIRFORPLUM@${dirForPLUM}@g" postproc.sh
    elif [[ ${runtype} == "lsf" ]]; then
        if [[ ! -f ${postproc_template} ]]; then
           echo "postproc_template file not found: ${postproc_template}"
           exit 1
        fi
        cp "${postproc_template}" postproc.sh
        # Replace placeholder(s)
        if [[ "${dirForPLUM}" == "" ]]; then
            echo "dirForPLUM unspecified"
            exit 1
        fi
        sed -i "s@DIRFORPLUM@${dirForPLUM}@g" postproc.sh
        sed -i "s@THISPOT@${thisPot}@g" postproc.sh
        sed -i "s@THISSSP@${thisSSP}@g" postproc.sh
        if [[ ${is_resuming} -eq 0 ]]; then
            sed -i "s@THISY1@$((y1 + Nyears_getready))@g" postproc.sh
        else
            sed -i "s@THISY1@${y1}@g" postproc.sh
        fi
        sed -i "s@THISYN@${yN}@g" postproc.sh
    else
        echo "rc_setup_potential_loop.sh doesn't know how to handle postproc for runtype ${runtype}" >&2
        exit 1
    fi

    if [[ $(grep "WWWW" main.ins | wc -l) -gt 0 ]]; then
        echo "WWWW not replaced with a number for save_years (even just a dummy)" >&2
        exit 1
    fi

    # Actually set up and even submit, if being called from within setup_all.sh
    if [[ ( ${pot_restart_year} -le ${hist_y1} || ${act_restart_year} -eq ${y1} || ${pot_restart_year} -eq ${future_y1} || ${pot_restart_year} -eq $((future_y1 - Nyears_getready)) ) && ${y1} -ne $(echo "${fut_save_years}" | awk '{print $NF}') ]]; then
        delete_state_arg=
    elif [[ "${never_delete_state_years}" == *"${pot_restart_year}"* ]]; then
        delete_state_arg=
    else
        echo WILL DELETE ${pot_restart_year} STATE

        delete_state_arg="--delete-state-year ${pot_restart_year}"
    fi
    if [[ ${actually_setup} -eq 1 ]]; then
        if [[ ${yN} -le ${hist_yN} ]]; then
            this_prefix="${prefix}_hist"
        else
            this_prefix="${prefix}_${thisSSP}"
        fi
        ispot=1
        do_setup ${walltime_pot} ${ispot} ${delete_state_arg}
    fi

    if [[ ${do_fu_only} -eq 0 ]]; then
        arr_job_name+=("${this_jobname}")
        if [[ "${submit}" != "" ]]; then
            this_jobnum=$(get_latest_run)
            arr_job_num+=(${this_jobnum})
            dependency_on_latest_potset+=" -d ${this_jobnum}"
            latest_pot_jobnum=${this_jobnum}
        fi
        arr_y1+=(${y1})
        arr_yN+=(${yN})
    elif [[ ${made_home_dir} -eq 1 ]]; then
        rm "${home_dir_realpath}/postproc.sh"
        rmdir "${home_dir_realpath}"
    fi

    if [[ ${is_resuming} -eq 1 ]]; then
        did_resume_pre2015pots[${thisSSP}]=$((did_resume_pre2015pots[${thisSSP}] + 1))
    fi

    popd 1>/dev/null

done


##############
### Finish ###
##############


echo " "
echo " "
cd ..
