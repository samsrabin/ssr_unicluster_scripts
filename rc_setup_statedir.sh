
state_path_hist="../states"

if [[ ! -d ${state_path_thisSSP} ]]; then
    mkdir -p ${state_path_thisSSP}
    pushd ${state_path_thisSSP} 1>/dev/null
    for y in ${hist_save_years}; do
        if [[ -L ${y} ]]; then
            rm -f ${y}
        fi
        if [[ "${runtype}" == "sai" && "${thisSSP}" != "ssp245" && ${y} -gt 2015 ]]; then
            ln -s ../states_ssp245.${ensemble_member_fut}/${y}
        else
            ln -s ${state_path_hist}/${y}
        fi
    done
    popd 1>/dev/null
fi

