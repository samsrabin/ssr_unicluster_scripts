
#echo " "
#echo rc_setup_statedir_pot.sh
#echo state_path_thisSSP $state_path_thisSSP

if [[ ${runtype} == "sai" && "${thisSSP}" != "hist" ]]; then
    state_path_thisSSP+=".${ensemble_member_fut}"
#echo state_path_thisSSP $state_path_thisSSP
fi

mkdir -p ${state_path_thisSSP}

pushd ${state_path_thisSSP} 1>/dev/null
if [[ -L ${y0} ]]; then
    rm -f ${y0}
fi

if [[ ${save_state_sai2035} -eq 1 ]]; then
    ln -s ../../actual/states_ssp245.${ensemble_member_fut}/${y0}
elif [[ "${histname}" != "hist" && ${y0} -gt ${hist_y1} ]]; then
    if [[ "${thisSSP}" != "${histname}" && ${y0} -gt ${future_y1} ]]; then
        ln -s ../../actual/states_${histname}/${y0}
    else
        ln -s ../../actual/states_${thisSSP}/${y0}
    fi
else
    ln -s ../../actual/states/${y0}
fi

popd 1>/dev/null

