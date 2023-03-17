
state_path_hist="../states"

if [[ ! -d ${state_path_thisSSP} ]]; then
    mkdir -p ${state_path_thisSSP}
    pushd ${state_path_thisSSP} 1>/dev/null
    for y in ${hist_save_years}; do
        if [[ -L ${y} ]]; then
            rm -f ${y}
        fi
        ln -s ${state_path_hist}/${y}
    done
    popd 1>/dev/null
fi

