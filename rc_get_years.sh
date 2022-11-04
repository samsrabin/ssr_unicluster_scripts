
# Get info for last XXXXpast_YYYYall_LU.txt
first_LUyear_past=$((first_pot_y1 - Nyears_getready))
last_LUyear_past=${first_LUyear_past}
last_LUyear_all=$((last_LUyear_past + 1))
y1=$((first_pot_y1 + pot_step))
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_y1} ]]; do
    last_LUyear_past=$((last_LUyear_past + pot_step))
    last_LUyear_all=$((last_LUyear_all + pot_step))
    y1=$((y1 + pot_step))
done
hist_yN=$((future_y1 - 1))
last_year_act_hist=$((last_LUyear_past - 1))
do_future_act=0
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -lt ${future_yN} ]]; do
    do_future_act=1
    last_LUyear_past=$((last_LUyear_past + pot_step))
    last_LUyear_all=$((last_LUyear_all + pot_step))
    y1=$((y1 + pot_step))
done
last_year_act_future=$((last_LUyear_past - 1))
if [[ ${do_future_act} -eq 1 ]]; then
    last_year_act_hist=${hist_yN}
fi

# Generate lists of start and end years for potential runs
list_pot_y1_hist=()
list_pot_y1_future=()
list_pot_yN_hist=()
list_pot_yN_future=()
#y1=${first_LUyear_past}
y0=${first_LUyear_past}
y1=$((first_LUyear_past + Nyears_getready))
yN=$((y1 + Nyears_pot - 1))
if [[ ${yN} -gt ${pot_yN} ]]; then
    yN=${pot_yN}
fi
i=0
list_pot_y0_future=()
while [[ ${do_hist} -eq 1 ]] && [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -le ${last_pot_y1} ]] && [[ ${yN} -lt ${future_y1} ]]; do
    list_pot_y1_hist+=(${y0})

    if [[ ${yN} -ge ${future_y1} ]]; then
        list_pot_yN_hist+=(${hist_yN})
        list_pot_y1_future+=(${future_y1})
        list_pot_yN_future+=(${yN})
        list_pot_y0_future+=(${y0})
        list_pot_save_state+=(1)
    else
        list_pot_yN_hist+=(${yN})
        list_pot_save_state+=(0)
    fi

    y0=$((y0 + pot_step))
    y1=$((y1 + pot_step))
    yN=$((yN + pot_step))
    if [[ ${yN} -gt ${pot_yN} ]]; then
        yN=${pot_yN}
    fi
done

h=-1
list_future_is_resuming=()
while [[ ${y1} -le ${pot_yN} ]] && [[ ${y1} -le ${last_pot_y1} ]] && [[ ${y1} -lt ${future_yN} ]]; do
    list_pot_save_state+=(0)
    if [[ ${yN} -gt ${pot_yN} ]]; then
        yN=${pot_yN}
    fi
    if [[ ${yN} -gt ${future_yN} ]]; then
        yN=${future_yN}
    fi

    if [[ ${y0} -lt ${future_y1} ]]; then
        if [[ ${do_hist} -eq 1 ]]; then
            list_pot_y1_hist+=(${y0})
            list_pot_yN_hist+=(${hist_yN})
        fi
        list_pot_y1_future+=(${future_y1})
        list_pot_yN_future+=(${yN})
        list_future_is_resuming+=(1)
        h=$((h+1))
        list_pot_y0_future+=(${y0})
    else
        list_pot_y1_future+=(${y0})
        list_pot_yN_future+=(${yN})
        list_future_is_resuming+=(0)
        list_pot_y0_future+=(9999)
    fi

    y0=$((y0 + pot_step))
    y1=$((y1 + pot_step))
    yN=$((yN + pot_step))
done

# Generate lists of states to save in historical and future periods
hist_save_years=
fut_save_years=
if [[ ${potential_only} -eq 0 ]]; then
    if [[ ${do_hist} -eq 1 ]]; then
        hist_save_years="${list_pot_y1_hist[@]}"
    fi
    added_future_y1=0
    i=-1
    for y in ${list_pot_y1_future[@]}; do
        i=$((i+1))
        is_resuming=${list_future_is_resuming[i]}
        if [[ ${is_resuming} -eq 1 ]]; then
            if [[ ${added_future_y1} -eq 0 ]]; then
                hist_save_years+=" ${future_y1}"
                added_future_y1=1
            fi
            continue
        elif [[ ${y} -ge ${future_y1} && "${hist_save_years}" != *"$((future_y1 - 1))"* ]]; then
            hist_save_years+=" ${future_y1}"
            added_future_y1=1
        elif [[ ${y} -le ${future_y1} ]]; then
            continue
        fi
        fut_save_years+=" ${y}"
    done

    echo "Saving states in actual runs at beginning of years:"
    if [[ ${do_hist} -eq 1 ]]; then
        echo "    Historical runs:" $hist_save_years
    fi
    if [[ ${do_future} -eq 1 ]]; then
        echo "        Future runs:" $fut_save_years
    fi
else
    echo "No actual runs."
fi
if [[ ${actual_only} -eq 0 ]]; then
    if [[ ${do_hist} -eq 1 ]]; then
        echo "Historical potential runs:"
        echo "    Begin:" ${list_pot_y1_hist[@]}
        echo "      End:" ${list_pot_yN_hist[@]}
    fi
    if [[ ${do_future} -eq 1 ]]; then
        echo "Future potential runs:"
        echo "       y0:" ${list_pot_y0_future[@]}
        echo "    Begin:" ${list_pot_y1_future[@]}
        echo "      End:" ${list_pot_yN_future[@]}
    fi
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Risk of filling up scratch space if saving too many states.
# Avoid this by splitting run into groups of at most maxNstates states.

# Historical states

# First, get the state(s) that happen during spinup, and split them from states
# in the transient period.
firsthistyear="$(get_param.sh template/${topinsfile} "firsthistyear")"
hist_save_years_spin=""
hist_save_years_trans="${hist_save_years}"
for y in ${hist_save_years}; do
    if [[ ${y} -gt ${firsthistyear} ]]; then
        break
    fi
    hist_save_years_spin="${hist_save_years_spin} ${y}"
    hist_save_years_trans=${hist_save_years_trans/${y}/}
done

# If running spinup period only, make sure to save a restart for firsthistyear
separate_spinup=0
if [[ $(echo ${hist_save_years_spin} | wc -w) -le $((maxNstates - 1)) && ${potential_only} -eq 0 ]]; then
    separate_spinup=1
    if [[ "$(echo ${hist_save_years_spin} | { grep "${firsthistyear}" || true; })" == "" ]]; then
        hist_save_years_spin="${hist_save_years_spin} ${firsthistyear}"
    fi
fi

# Split each save_years list up as needed given maxNstates
if [[ ${potential_only} -eq 0 ]]; then
    hist_save_years_lines="$(xargs -n ${maxNstates} <<< ${hist_save_years_spin})"$'\n'"$(xargs -n ${maxNstates} <<< ${hist_save_years_trans})"
    fut_save_years_lines="$(xargs -n ${maxNstates} <<< ${fut_save_years})"
    if [[ $((do_hist + do_future)) -eq 2 ]]; then
        save_years_lines="${hist_save_years_lines}
${fut_save_years_lines}"
    elif [[ ${do_hist} -eq 1 ]]; then
        save_years_lines="${hist_save_years_lines}"
    elif [[ ${do_future} -eq 1 ]]; then
        save_years_lines="${fut_save_years_lines}"
    fi
else
    if [[ $((do_hist + do_future)) -eq 2 ]]; then
        save_years_lines="${list_pot_y1_hist[@]}
${list_pot_y1_future[@]}"
    elif [[ ${do_hist} -eq 1 ]]; then
        save_years_lines="${list_pot_y1_hist[@]}"
    elif [[ ${do_future} -eq 1 ]]; then
        save_years_lines="${list_pot_y1_future[@]}"
    fi
fi
