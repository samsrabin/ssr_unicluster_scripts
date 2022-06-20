# Set up state directory for this SSP, if needed
# IF YOU WIND UP WITH PROBLEMS HERE, CONSIDER USING THIS FUNCTIONALITY
# BUILT IN TO lsf_setup_1run.sh INSTEAD!
# I.e., -L flag
# Would need to ensure that it's ONLY used for first part of future runs (if splitting ssp period).


state_path=""
state_path_absolute=$(lsf_get_state_path_absolute.sh "${rundir_top}" "${state_path_absolute}")
if [[ ${ispot} -eq 0 ]]; then
    state_path_thisSSP="${state_path_absolute}_${thisSSP}"
fi

. lsf_setup_statedir.sh

