# Set up state directory for this SSP, if needed
# IF YOU WIND UP WITH PROBLEMS HERE, CONSIDER USING THIS FUNCTIONALITY
# BUILT IN TO lsf_setup_1run.sh INSTEAD!
# I.e., -L flag
# Would need to ensure that it's ONLY used for first part of future runs (if splitting ssp period).


state_path=""
state_path_absolute=$(lsf_get_state_path_absolute.sh "${rundir_top}" "${state_path_absolute}")
state_path_thisSSP="${state_path_absolute}_${thisSSP}"
if [[ ! -d ${state_path_thisSSP} ]]; then
    mkdir -p ${state_path_thisSSP}
    pushd ${state_path_thisSSP} 1>/dev/null
    for y in ${hist_save_years}; do
        if [[ -L ${y} ]]; then
            rm -f ${y}
        fi
        ln -s ../states/${y}
    done
    popd 1>/dev/null
fi
