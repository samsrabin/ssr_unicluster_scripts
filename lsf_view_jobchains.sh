#!/bin/bash
set -e

runset_ver="runs-2022-05"
symbol_norun="--"            # No run started for this period within this job chain.
symbol_runna=" "            # Run not applicable for this period (U+2002 EN SPACE)
symbol_pend_depend="👀"      # Pending: waiting on dependency
symbol_pend_other="⏳"       # Pending: other reason
symbol_running="🏃"          # Job is currently running
symbol_ok="✅"               # Job completed successfully
symbol_canceled_manual="🙅"  # Job was canceled by user
symbol_canceled_auto="☹️ "    # Job canceled itself (postprocessing recognized failed model run)
symbol_timeout="🛑"          # Job reached maximum walltime
symbol_failed="❌"           # Job failed
symbol_unknown="❓"          # Job didn't seem to fail or have been canceled
symbol_unknown2="⁉️ "         # Job not found by sacct

# Set default values for non-positional arguments
testing=0
verbose=0
work_cols=1
gcmlist="gfdl ipsl mpi mri ukesm"

# Args while-loop
while [ "$1" != "" ];
do
    case $1 in
        -g  | --gcmlist)
            shift
            gcmlist="$1"
            ;;
        -h  | --home-cols)
            work_cols=0
            ;;
        -t  | --test)
            testing=1
            ;;
        -v  | --verbose)
            verbose=1
            ;;
        *)
            echo "$script: illegal option $1"
            usage
            exit 1 # error
            ;;
    esac
    shift
done

pushdq () {
    command pushd "$@" > /dev/null
}

popdq () {
    command popd "$@" > /dev/null
}

# Helper functions to allow passing latest_job out of get_symbol function.
# https://stackoverflow.com/a/47556292/2965321
_passback() { while [ 1 -lt $# ]; do printf '%q=%q;' "$1" "${!1}"; shift; done; return $1; }
passback() { _passback "$@" "$?"; }
_capture() { { out="$("${@:2}" 3<&-; "$2_" >&3)"; ret=$?; printf "%q=%q;" "$1" "$out"; } 3>&1; echo "(exit $ret)"; }
capture() { eval "$(_capture "$@")"; }


jobs=$(squeue -o "%P %i %j %T %r")

#function string_contains {
#	result=0
#	if [[ $1 == *"${2}"* ]]; then
#		result=1
#	fi
#	echo $result
#}

function check_sacct {
    jobnum=$1
    checkstatus=$2

    # Check whether we've already sacct'd this run; if not, do so
    sacct_file=sacct.${jobnum}
    if [[ ! -e ${sacct_file} ]]; then
        sacct -n -j $jobnum > ${sacct_file}
    fi

    sacct_result="$(cat ${sacct_file})"
    if [[ "${sacct_result}" == "" ]]; then
        echo -1
    else
        echo "${sacct_result}" | grep -E "^${jobnum}\s" | grep "${checkstatus}" | wc -l
    fi
}

function get_symbol_() { passback latest_job; }

function get_symbol() {
    workdir="$(get_equiv_workdir.sh "$PWD")/${homedir_rel}"
    if [[ ${testing} -eq 1 && "${PWD}" != *"_test" ]]; then
        workdir="$(get_equiv_workdir.sh "$PWD")_test/${homedir_rel}"
    else
        workdir="$(get_equiv_workdir.sh "$PWD")/${homedir_rel}"
    fi

    # workdir does NOT exist
    if [[ ! -d "${workdir}" ]]; then
        symbol="${symbol_norun}"

        # workdir DOES exist
    else
        pushdq "${workdir}"
        workdir_short=$(echo $workdir | sed "s@${WORK}@\$WORK@")

        matching_jobs=$(echo "${jobs}" | { grep -E "\s${thepattern}" || true; })
        # Kludge
        if [[ "${matching_jobs}" == "" ]]; then
            thepattern=$(echo $thepattern | sed "s/${ssp}/${ssp}_${ssp}/");
            matching_jobs=$(echo "${jobs}" | { grep -E "\s${thepattern}" || true; })
        fi

        # There are NO matching jobs
        if [[ "${matching_jobs}" == "" ]]; then


            # latest_submitted_jobs.log doesn't actually exist yet
            if [[ ! -e latest_submitted_jobs.log ]]; then
                symbol="${symbol_norun}"

            # SIMULATION
            elif [[ "${thepattern:0:6}" != "jobfin" ]]; then
                latest_job=$(grep "LPJ-GUESS run" latest_submitted_jobs.log | awk 'END {print $NF}')

                # Check statuses from sacct
                was_it_canceled=$(check_sacct ${latest_job} "CANCEL")
                timed_out=$(check_sacct ${latest_job} "TIMEOUT")
                status=$(echo ${matching_jobs} | cut -d' ' -f4)
                if [[ "${status}" == "PENDING" ]]; then
                    if [[ $(echo ${matching_jobs} | grep "Dependency" | wc -l) -gt 0 ]]; then
                        symbol="${symbol_pend_depend}"
                    else
                        symbol="${symbol_pend_other}"
                    fi
                elif [[ "${status}" == "CONFIGURING" || "${status}" == "RUNNING" || "${status}" == "COMPLETING" ]]; then
                    symbol="${symbol_running}"
                elif [[ ${was_it_canceled} -gt 0 ]]; then
                    symbol="${symbol_canceled_manual}"

                # Check if it timed out
                elif [[ ${timed_out} -gt 0 ]]; then
                    symbol="${symbol_timeout}"

                    # If no run was started in this chain, then say so
                elif [[ ${latest_job} -lt ${latest_actual_job} ]]; then
                    fakefile=${latest_job}.fakelastactual_${latest_actual_job}
                    # Sometimes you rerun an actual job but you don't need to rerun the potentials.
                    if [[ -e $fakefile ]]; then
                        symbol="${symbol_ok}"
                        #... but sometimes you just never ran the potential.
                    else
                        symbol="${symbol_norun}"
                    fi

                    # Otherwise, check if simulation began
                else
                    file_stdout="guess_x.o${latest_job}"
                    # If not, assume it was canceled before beginning.
                    if [[ ! -e "${file_stdout}" ]]; then
                        was_it_canceled=$(check_sacct ${latest_job} "CANCEL")
                        if [[ ${was_it_canceled} -lt 0 ]]; then
                            symbol="${symbol_unknown2}"
                            >&2 echo "${symbol} stdout file not found: ${workdir_short}/${file_stdout}"
                        elif [[ ${was_it_canceled} -eq 0 ]]; then
                            symbol="${symbol_unknown}"
                            >&2 echo "${symbol} stdout file not found: ${workdir_short}/${file_stdout}"
                        else
                            symbol="${symbol_canceled_manual}"
                        fi
                        # Otherwise, check if we've already processed this stdout
                    elif [[ -e ${file_stdout}.ok ]]; then
                        symbol="${symbol_ok}"
                    elif [[ -e ${file_stdout}.canceled_manual ]]; then
                        symbol="${symbol_canceled_manual}"
                    elif [[ -e ${file_stdout}.fail ]]; then
                        if [[ ${verbose} -eq 1 ]]; then
                            cat ${file_stdout}.fail >&2
                        fi
                        symbol="${symbol_failed}"
                        # Otherwise...
                    else
                        # Was job canceled?
                        if [[ $(tail -n 100 ${file_stdout} | grep "State: CANCELLED" | wc -l) -ne 0 ]]; then
                            symbol="${symbol_canceled_manual}"
                            touch ${file_stdout}.canceled_manual

                            # Did job fail?
                        elif [[ $(tail -n 100 ${file_stdout} | grep "State: FAILED\|State: NODE_FAIL" | wc -l) -ne 0 ]]; then
                            echo "${symbol_failed} $PWD/${file_stdout} has State indicating failure" > ${file_stdout}.fail
                            if [[ ${verbose} -eq 1 ]]; then
                                cat ${file_stdout}.fail >&2
                            fi
                            symbol="${symbol_failed}"

                            # Otherwise...
                        else
                            # Check whether all processes completed successfully
                            nnodes=$(grep "Data for node" "${file_stdout}" | wc -l)
                            nprocs=0
                            this_nprocs=$(grep "Data for node" "${file_stdout}" | grep -oE "[0-9]+$")
                            for x in ${this_nprocs}; do
                                nprocs=$((nprocs + x))
                            done
                            if [[ "${nprocs}" == "" ]]; then
                                >&2 echo "Error getting nprocs from $(realpath ${file_stdout}): blank!"
                                exit 17
                            elif [[ ${nprocs} -eq 0 ]]; then
                                >&2 echo "Error getting nprocs from $(realpath ${file_stdout}): nprocs = 0"
                                exit 17
                            fi
                            nfinished=$(grep "Finished" ${file_stdout} | grep -v "Finished with" | wc -l )
                            nunfinished=$((nprocs - nfinished))

                            # If all processes completed with "Finished" message, that's great!
                            if [[ $nprocs == $nfinished ]]; then
                                symbol="${symbol_ok}"
                                touch ${file_stdout}.ok


                            # Otherwise, assume run failed.
                            else
                                echo "${symbol_failed} Not all processes in $(pwd) ended with 'Finished'" > ${file_stdout}.fail
                                if [[ ${verbose} -eq 1 ]]; then
                                    cat ${file_stdout}.fail >&2
                                fi
                                symbol="${symbol_failed}"
                            fi
                        fi # Was it canceled before beginning?

                    fi # Was it canceled before opening stdout?
                fi # Was a run started in this chain?

                # JOBFIN
            else
                latest_job=$(grep "job_finish" latest_submitted_jobs.log | awk 'END {print $NF}')

                # If no run was started in this chain, then say so
                if [[ ${latest_job} == "" || ${latest_job} -lt ${latest_actual_job} ]]; then
                    fakefile=${latest_job}.fakelastactual_${latest_actual_job}
                    # Sometimes you rerun an actual job but you don't need to rerun the potentials.
                    if [[ -e $fakefile ]]; then
                        symbol="${symbol_ok}"
                        #... but sometimes you just never ran the potential.
                    else
                        symbol="${symbol_norun}"
                    fi

                    # Otherwise, check if simulation began
                else
                    file_stdout="job_finish.${latest_job}.log"
                    if [[ ! -e "${file_stdout}" ]]; then
                        was_it_canceled=$(check_sacct ${latest_job} "CANCEL")
                        if [[ ${was_it_canceled} -lt 0 ]]; then
                            symbol="${symbol_unknown2}"
                            >&2 echo "${symbol} stdout file not found: ${workdir_short}/${file_stdout}"
                        elif [[ ${was_it_canceled} -eq 0 ]]; then
                            symbol="${symbol_unknown}"
                            >&2 echo "${symbol} stdout file not found: ${workdir_short}/${file_stdout}"
                        else
                            symbol="${symbol_canceled_manual}"
                        fi
                    else

                        timed_out=$(check_sacct ${latest_job} "TIMEOUT")

                        # Completed successfully?
                        if [[ $(tail -n 20 ${file_stdout} | grep "All done\!" | wc -l) -gt 0 ]]; then
                            symbol="${symbol_ok}"

                            # If not, was job canceled automatically?
                        elif [[ $(head ${file_stdout} | grep "Canceling because" | wc -l) -gt 0 ]]; then
                            symbol="${symbol_canceled_auto}"

                            # If not, was job canceled manually?
                        elif [[ $(tail -n 100 ${file_stdout} | grep "State: CANCELLED" | wc -l) -ne 0 ]]; then
                            symbol="${symbol_canceled_manual}"

                        # Check if it timed out
                        elif [[ ${timed_out} -gt 0 ]]; then
                            symbol="${symbol_timeout}"

                            # Otherwise, assume run failed.
                        else
                            echo "${symbol_failed} ${PWD} job_finish failed: Some other reason?" > ${file_stdout}.fail
                            if [[ ${verbose} -eq 1 ]]; then
                                cat ${file_stdout}.fail >&2
                            fi
                            symbol="${symbol_failed}"
                        fi
                    fi # Does stdout file exist?
                fi # Was a run started in this chain?	
            fi # Is it a simulation or jobfin?

            # There ARE matching jobs
        else
            latest_job=$(echo ${matching_jobs} | cut -d' ' -f2)
            status=$(echo ${matching_jobs} | cut -d' ' -f4)
            if [[ "${status}" == "PENDING" ]]; then
                if [[ $(echo ${matching_jobs} | grep "Dependency" | wc -l) -gt 0 ]]; then
                    symbol="${symbol_pend_depend}"
                else
                    symbol="${symbol_pend_other}"
                fi
            elif [[ "${status}" == "CONFIGURING" || "${status}" == "RUNNING" || "${status}" == "COMPLETING" ]]; then
                symbol="${symbol_running}"
            else
                >&2 echo ${matching_jobs}
                >&2 echo "status ${status} not recognized"
                exit 2
            fi # What's the job status?
        fi # Are there matching jobs?
        popdq
    fi # Does workdir exist?

    echo $symbol
}

function check_jobs {

    # Model run
    thepattern="${1}"
    capture newpart get_symbol "${thisstatus}"
    thisline="${thisline} ${newpart}"

    # Postprocessing
    thepattern="jobfin_${thepattern}"
    capture newpart get_symbol "${thisstatus}"
    thisline="${thisline}/${newpart}"

}

function get_act_col_heads {
    pushdq "${d}"
    runset_workdir="$(get_equiv_workdir.sh "$PWD")"
    if [[ ${testing} -eq 1 ]]; then
        runset_workdir+="_test"
    fi
    if [[ ${work_cols} -eq 1 ]]; then
        pushdq "${runset_workdir}"
    fi
    if [[ "${ssp}" == "hist" ]]; then
        testSSP="hist"
        col_code="ACTH"
    else
        col_code="ACTF"
        testSSP="$(ls -1 "actual" | grep -oE "ssp[0-9]+" | sort | uniq | head -n 1)"
    fi
    theseactdirs=$(ls -d "actual/${testSSP}_"* | grep -vE "\.tar$")
    if [[ ${work_cols} -eq 1 ]]; then
        popdq
    fi
    if [[ "${theseactdirs}" == "" ]]; then
        echo "get_act_col_heads: No directories found matching ${d}/actual/${testSSP}_*" >&2
        exit 1
    fi

    # If there's a "spin" directory, put it on top
    spinline="$(echo -e "${theseactdirs}" | grep "hist_spin")"
    if [[ "${spinline}" != "" ]]; then
        theseactdirs="${spinline}"$'\n'"$(echo -e "${theseactdirs}" | grep -v "hist_spin")"
    fi

    Nact=0
    act_col_heads=""
    for d_act in ${theseactdirs}; do
        Nact=$((Nact + 1))
        act_col_heads="${act_col_heads}${col_code}${Nact},"
    done
    echo "${act_col_heads}"
}

cd "/home/kit/imk-ifu/lr8247/landsymm/runs-forestonly/${runset_ver}"

tmpfile=.tmp.lsf_view_jobchains.$(date +%N)
touch $tmpfile

hist_act_col_heads=""
future_act_col_heads=""
pot_col_heads=""
for g in ${gcmlist}; do
    if ! compgen -G "${g}"*/ >/dev/null; then
        continue
    fi
    dirlist=$(ls -d "${g}"* | grep -v "calibration\|_test\|\.sh")
    for d in ${dirlist}; do
        islast_act=0
    
        # If this directory doesn't even have a working directory set up, you can skip
        thischain_workdir="$(get_equiv_workdir.sh "$(realpath $d)")"
        if [[ ${testing} -eq 1 ]]; then
            thischain_workdir="${thischain_workdir}_test"
        fi
        if [[ ! -d ${thischain_workdir} ]]; then
            [[ ${verbose} -eq 1 ]] && echo "thischain_workdir ${thischain_workdir} not found; skipping"
            continue
        fi
    
        # Get short name for this chain
        thischain_name="$(lsf_chain_shortname.sh ${d} ${testing})"

        # Get potential run names
        if [[ ${work_cols} -eq 1 ]]; then
            equiv_workdir="$(get_equiv_workdir.sh "${d}")"
            if [[ ${testing} -eq 1 ]]; then
                equiv_workdir+="_test"
            fi
            pushdq "${equiv_workdir}"
        else
            pushdq "${d}"
        fi
        if [[ -d "potential" ]]; then
            pot_run_names="$(find "potential" -type d -name "*pot_*" 2>/dev/null | cut -d"/" -f3 | grep -oE "[0-9]+pot" | sort | uniq)"
            if [[ -d "potential/hist" ]]; then
                hist_pot_run_names="$(find potential/hist -type d -name "*pot_*" | cut -d"/" -f3 | grep -oE "[0-9]+pot" | sort | uniq)"
            else
                hist_pot_run_names=""
            fi
            future_pot_run_names="$(find potential/ssp* -type d -name "*pot_*" | cut -d"/" -f3 | grep -oE "[0-9]+pot" | sort | uniq)"
        else
            pot_run_names=""
        fi
        popdq
        
#        ssp_list="hist ssp126 ssp370 ssp585"
        ssp_list="hist ssp126"
        s=0
        latest_job=""
        latest_actual_job="-1"
        for ssp in ${ssp_list}; do
            s=$((s+1))
            if [[ ${ssp} == $(echo ${ssp_list} | grep -oE '[^ ]+$') ]]; then
                islast_act=1
            else
                islast_act=0
            fi

            # Get historical column headers, if necessary
            if [[ "${ssp}" == "hist" && "${hist_act_col_heads}" == "" ]]; then
                hist_act_col_heads="$(get_act_col_heads)"
                hist_col_heads="${hist_act_col_heads}$(echo ${hist_pot_run_names} | sed "s/pot/p/g" | sed "s/ /,/g"),"
            fi

            # Get future column headers, if necessary
            if [[ "${ssp}" != "hist" && "${future_act_col_heads}" == "" ]]; then
                future_act_col_heads="$(get_act_col_heads)"
                future_col_heads="${future_act_col_heads}$(echo ${future_pot_run_names} | sed "s/pot/p/g" | sed "s/ /,/g"),"
            fi

            # Get potential column headers, if necessary
            if [[ "${pot_col_heads}" == "" ]]; then
                pot_col_heads="$(echo ${pot_run_names} | sed "s/ot//g" | sed "s/ /,/g")"
            fi

    
            # Set up beginning of line if necessary
            if [[ $s -eq 1 ]]; then
                thisline="${thischain_name} "
            elif [[ $s -gt 2 ]]; then
                thisline=" :"
            fi

            # Get actual periods
            if [[ ${work_cols} -eq 1 ]]; then
                runset_workdir="$(get_equiv_workdir.sh "$PWD/${d}")"
                if [[ ${testing} -eq 1 ]]; then
                    runset_workdir+="_test"
                fi
                pushdq "${runset_workdir}"
            else
                pushdq "${d}"
            fi
            theseactdirs=$(ls -d "actual/${ssp}_"* | grep -vE "\.tar$")
            if [[ "${theseactdirs}" == "" ]]; then
                echo "No directories found matching ${d}/actual/${ssp}_*"
                exit 1
            fi
            # If there's a "spin" directory, put it on top
            spinline="$(echo -e "${theseactdirs}" | { grep "hist_spin" || true; })"
            if [[ "${spinline}" != "" ]]; then
                theseactdirs="${spinline}"$'\n'"$(echo -e "${theseactdirs}" | grep -v "hist_spin")"
            fi
        
            # Check actual periods
            x=0
            for d_act in ${theseactdirs}; do
                x=$((x + 1))
                homedir_rel="${d_act}"
                if [[ $x -eq 1 && "${ssp}" != "hist" ]]; then
                    thisline="${thisline} ${ssp/ssp/}"
                fi
                check_jobs ${thischain_name}_$(basename ${d_act})_
                if [[ ${latest_job} -gt ${latest_actual_job} ]]; then
                    latest_actual_job=${latest_job}
                fi
            done
            popdq

            # Get potential periods
            if [[ ${work_cols} -eq 1 ]]; then
                equiv_workdir="$(get_equiv_workdir.sh "${d}")"
                if [[ ${testing} -eq 1 ]]; then
                    equiv_workdir+="_test"
                fi
                pushdq "${equiv_workdir}"
            else
                pushdq "${d}"
            fi
            potdir="potential/${ssp}/"
            if [[ ! -d "${potdir}" ]]; then
                #echo "Skipping ${potdir} (directory not found)"
                if [[ "${ssp}" != "hist" ]]; then
                    echo ${thisline} >> $tmpfile
                fi
                popdq
                continue
            fi
            pot_list=$(ls "${potdir}" | cut -d' ' -f1-2 | grep -vE "\.tar$")
            if [[ "${ssp}" == "hist" ]]; then
                these_pot_run_names="${hist_pot_run_names}"
            else
                these_pot_run_names="${future_pot_run_names}"
            fi
            popdq

            # Check potential periods
            pushdq "${d}"
            for pot in ${these_pot_run_names}; do
                p_found=0
                for p in ${pot_list}; do
                    if [[ "${p}" == "${pot}"* ]]; then
                        p_found=1
                        break
                    fi
                done
                if [[ ${p_found} -eq 1 ]]; then
                    homedir_rel="potential/${ssp}/${p}"
                    check_jobs ${thischain_name}_${ssp}_${pot}
                else
                    thisline="${thisline} ${symbol_runna}"
                fi
            done
            popdq

            if [[ "${ssp}" != "hist" ]]; then
                echo ${thisline} >> $tmpfile
            fi
        done
    done
done

cat $tmpfile | column --table --table-columns RUNSET,${hist_col_heads},SSP,${future_col_heads} -s ": "

rm $tmpfile

exit 0
