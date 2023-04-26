
state_path_hist="../states"

echo state_path_thisSSP $state_path_thisSSP

#if [[ ! -d ${state_path_thisSSP} ]]; then
    echo rc_setup_statedir.sh
    mkdir -p ${state_path_thisSSP}
    pushd ${state_path_thisSSP} 1>/dev/null
    for y in ${hist_save_years}; do
        echo y $y
        if [[ -L ${y} ]]; then
            rm -f ${y}
        fi
        if [[ "${runtype}" == "sai" && "${thisSSP}" != "ssp245"* && ${y} -gt 2015 ]]; then
            echo thisSSP $thisSSP
            ln -s ../states_ssp245.${ensemble_member_fut}/${y}
        elif [[ ! ( "${runtype}" == "sai" && "${thisSSP}" == "ssp245"* ) || ${y} -le 2015 ]]; then
            ln -s ${state_path_hist}/${y}
        fi
    done

    if [[ "${runtype}" == "sai" && "${thisSSP}" == "ssp245"* && ${act_restart_year} -eq 2015 ]]; then
        if [[ -L ${act_restart_year} ]]; then
            rm -f ${act_restart_year}
        fi
        ln -s ${state_path_hist}/${act_restart_year}
    fi

    popd 1>/dev/null
#else
#    echo SKIPING rc_setup_statedir.sh
#fi

