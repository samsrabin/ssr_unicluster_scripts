
mkdir -p ${state_path_thisSSP}
pushd ${state_path_thisSSP} 1>/dev/null
for y in ${hist_save_years}; do
    if [[ -L ${y} ]]; then
        rm -f ${y}
    fi
    ln -s ../states/${y}
done
if [[ "${parent_script}" == "lsf_1_actfut.sh" ]]; then
    y=${future_y1}
    if [[ -L ${y} ]]; then
        rm -f ${y}
    fi
    ln -s ../states/${y}
fi
popd 1>/dev/null

