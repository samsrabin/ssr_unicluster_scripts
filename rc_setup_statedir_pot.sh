
#echo state_path_thisSSP $state_path_thisSSP
#exit 1

if [[ ${runtype} == "sai" ]]; then
    state_path_thisSSP+=".${ensemble_member_fut}"
fi

mkdir -p ${state_path_thisSSP}

pushd ${state_path_thisSSP} 1>/dev/null
if [[ -L ${y0} ]]; then
    rm -f ${y0}
fi
ln -s ../../actual/states/${y0}
popd 1>/dev/null

