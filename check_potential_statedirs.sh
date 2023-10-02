#!/bin/bash

for d in */; do
    if [[ "${d}" == "states"* ]]; then
        continue
    fi
    for d2 in "${d}"*/; do
        # Only include segments that actually save state
        if [[ "$(grep -E "save_state\s+1" "${d2}/main.ins")" == "" ]]; then
            continue
        fi
        statedir="$(grep -E "^mpirun " "${d2}/submit.sh" | cut -d" " -f 8)"
        if [[ "${statedir}" == *"actual/states_ssp245.001"* ]]; then
            symbol="🔴"
        else
            symbol="✅"
        fi
        echo "${d2} ${symbol} ${statedir}"
        echo " "
    done
done

exit 0
