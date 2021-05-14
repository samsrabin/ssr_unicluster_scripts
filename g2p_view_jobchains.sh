#!/bin/bash
set -e

remap_code_ver="remap12_2016"
symbol_norun="--"            # No run started for this period within this job chain.
symbol_pend_depend="👀"      # Pending: waiting on dependency
symbol_pend_other="⏳"       # Pending: other reason
symbol_running="🏃"          # Job is currently running
symbol_ok="✅"               # Job completed successfully
symbol_canceled_manual="🙅"  # Job was canceled by user
symbol_canceled_auto="☹️ "    # Job canceled itself (postprocessing recognized failed model run)
symbol_failed="❌"           # Job failed
symbol_unknown="❓"          # Job didn't seem to fail or have been canceled
symbol_unknown2="⁉️ "         # Job not found by sacct

# Set default values for non-positional arguments
testing=0

# Args while-loop
while [ "$1" != "" ];
do
    case $1 in
        -t  | --test)
            testing=1
            ;;
        *)
            echo "$script: illegal option $1"
            usage
            exit 1 # error
            ;;
    esac
    shift
done

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
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

function was_canceled {
    jobnum=$1

    # Check whether we've already sacct'd this run; if not, do so
    sacct_file=sacct.${jobnum}
    if [[ ! -e ${sacct_file} ]]; then
        sacct -n -j $jobnum > ${sacct_file}
    fi

    sacct_result="$(cat ${sacct_file})"
    if [[ "${sacct_result}" == "" ]]; then
        echo -1
    else
        echo "${sacct_result}" | grep "CANCEL" | wc -l
    fi
}

function get_symbol_() { passback latest_job; }

function get_symbol() {
    # First, change to working directory
    if [[ ! -d "${homedir_rel}" ]]; then
        >&2 echo "homedir_rel not found: ${homedir_rel}"
        >&2 echo "pwd: $PWD"
        exit 14
    fi
    homedir_rel_tmp=
    if [[ $testing -eq 0 ]]; then 
        homedir_rel_tmp="${homedir_rel}"
    else
        homedir_rel_tmp=$(echo "${homedir_rel}" | sed "s@/@_test/@")
    fi
    workdir="$(pwd | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")/${homedir_rel_tmp}"

    # workdir does NOT exist
    if [[ ! -d "${homedir_rel_tmp}" && ! -d "${workdir}" ]]; then
        symbol="${symbol_norun}"

        # workdir DOES exist
    else
        pushd "${workdir}"
        workdir_short=$(echo $workdir | sed "s@${WORK}@\$WORK@")

        matching_jobs=$(echo "${jobs}" | { grep -E "\s${thepattern}" || true; })

        # There are NO matching jobs
        if [[ "${matching_jobs}" == "" ]]; then

            # SIMULATION
            if [[ "${thepattern:0:6}" != "jobfin" ]]; then
                latest_job=$(grep "LPJ-GUESS run" latest_submitted_jobs.log | awk 'END {print $NF}')

                # Check if it was canceled
                was_it_canceled=$(was_canceled ${latest_job})
                if [[ ${was_it_canceled} -gt 0 ]]; then
                    symbol="${symbol_canceled_manual}"

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
                        was_it_canceled=$(was_canceled ${latest_job})
                        if [[ ${was_it_canceled} -lt 0 ]]; then
                            symbol="${symbol_unknown2}"
                        elif [[ ${was_it_canceled} -eq 0 ]]; then
                            symbol="${symbol_unknown}"
                        else
                            symbol="${symbol_canceled_manual}"
                        fi
                        # Otherwise, check if we've already processed this stdout
                    elif [[ -e ${file_stdout}.ok ]]; then
                        symbol="${symbol_ok}"
                    elif [[ -e ${file_stdout}.canceled_manual ]]; then
                        symbol="${symbol_canceled_manual}"
                    elif [[ -e ${file_stdout}.fail ]]; then
                        symbol="${symbol_failed}"
                        # Otherwise...
                    else
                        # Was job canceled?
                        if [[ $(tail -n 100 ${file_stdout} | grep "State: CANCELLED" | wc -l) -ne 0 ]]; then
                            symbol="${symbol_canceled_manual}"
                            touch ${file_stdout}.canceled_manual

                            # Did job fail?
                        elif [[ $(tail -n 100 ${file_stdout} | grep "State: FAILED" | wc -l) -ne 0 ]]; then
                            symbol="${symbol_failed}"
                            touch ${file_stdout}.fail

                            # Otherwise...
                        else
                            # If all cells completed with "Finished" message, that's great!
                            nprocs=$({ head "${file_stdout}" | grep -oE "Total slots allocated [0-9]+" | grep -oE "[0-9]+" || true; })
                            if [[ "${nprocs}" == "" ]]; then
                                >&2 echo "Error getting nprocs from $(realpath ${file_stdout})"
                                exit 17
                            fi
                            nfinished=$(grep "Finished" ${file_stdout} | grep -v "Finished with" | wc -l )
                            nunfinished=$((nprocs - nfinished))
                            if [[ $nprocs == $nfinished ]]; then
                                symbol="${symbol_ok}"
                                touch ${file_stdout}.ok


                                # Otherwise, assume run failed.
                            else
                                symbol="${symbol_failed}"
                                touch ${file_stdout}.fail
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
                        was_it_canceled=$(was_canceled ${latest_job})
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

                        # Completed successfully?
                        if [[ $(tail -n 20 ${file_stdout} | grep "All done\!" | wc -l) -gt 0 ]]; then
                            symbol="${symbol_ok}"

                            # If not, was job canceled automatically?
                        elif [[ $(head ${file_stdout} | grep "Canceling because" | wc -l) -gt 0 ]]; then
                            symbol="${symbol_canceled_auto}"

                            # If not, was job canceled manually?
                        elif [[ $(tail -n 100 ${file_stdout} | grep "State: CANCELLED" | wc -l) -ne 0 ]]; then
                            symbol="${symbol_canceled_manual}"

                            # Otherwise, assume run failed.
                        else
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
        popd
    fi # Does workdir exist?

    echo $symbol
}

function check_jobs {

    # Model run
    thepattern="${1}"
    capture newpart get_symbol "${thisstatus}"
    thisline="${thisline} ${newpart}"
    #	echo $thisline

    # Postprocessing
    thepattern="jobfin_${thepattern}"
    capture newpart get_symbol "${thisstatus}"
    thisline="${thisline}/${newpart}"
    #	echo $thisline

}

cd "/home/kit/imk-ifu/lr8247/g2p/runs/${remap_code_ver}"

tmpfile=.tmp.g2p_view_jobchains.$(date +%N)
touch $tmpfile

dirlist=$(ls | grep -v "calibration\|_test\|\.sh")
act_col_heads=""
pot_col_heads=""
for d in ${dirlist}; do
    islast_act=0

    # If this directory doesn't even have a working directory set up, you can skip
    thischain_workdir=$(realpath $d | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
    if [[ ${testing} -eq 1 ]]; then
        thischain_workdir="${thischain_workdir}_test"
    fi
    if [[ ! -d ${thischain_workdir} ]]; then
        echo "thischain_workdir ${thischain_workdir} not found; skipping"
        continue
    fi

    # Get short name for this chain
    thischain_name="$(g2p_chain_shortname.sh ${d} ${testing})"

    actdir="${d}/actual"
    if [[ ! -d "${actdir}" ]]; then
        echo "actdir not found: ${PWD}/${actdir})"
        exit 13
    fi
    ssp_list="ssp126 ssp370 ssp585"
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

        # Get potential column headers, if necessary
        potdir="${d}/potential/${ssp}/"
        if [[ ! -d "${potdir}" ]]; then
            #echo "Skipping ${potdir} (directory not found)"
            continue
        fi
        if [[ "${pot_col_heads}" == "" ]]; then
            pot_col_heads="$(echo $(ls "${potdir}") | sed "s/ /,/g")"
            pot_col_heads="$(echo ${pot_col_heads} | sed "s/^20/,/g" | sed "s/,20/,/g" | sed "s/-20/-/g")"
        fi

        # Check historical period, if necessary
        if [[ $s -eq 1 ]]; then
            homedir_rel="${d}/actual/hist"
            thisline="${thischain_name} "
            check_jobs ${thischain_name}_hist
        else
            thisline=" :"
        fi

        # Get future-actual periods
        futureactdirs=$(ls -d "${d}/actual/${ssp}_"*)
        if [[ "${futureactdirs}" == "" ]]; then
            echo "No directories found matching ${d}/actual/${ssp}_*"
            exit 1
        fi

        # Check future-actual periods
        x=0
        get_act_col_heads=0
        if [[ "${act_col_heads}" == "" ]]; then
            get_act_col_heads=1
        fi
        for d_act in ${futureactdirs}; do
            x=$((x + 1))
            if [[ $get_act_col_heads -eq 1 ]]; then
                act_col_heads="${act_col_heads}ACT${x},"
            fi

            homedir_rel="${d_act}"
            if [[ $x -eq 1 ]]; then
                thisline="${thisline} ${ssp/ssp/}"
            fi
            check_jobs ${thischain_name}_$(basename ${d_act})_
            if [[ ${latest_job} -gt ${latest_actual_job} ]]; then
                latest_actual_job=${latest_job}
            fi
        done

        # Check potential periods
        pot_list=$(ls "${potdir}" | cut -d' ' -f1-2)
        for pot in ${pot_list}; do
            homedir_rel="${d}/potential/${ssp}/${pot}"
            check_jobs ${thischain_name}_${ssp}_${pot}
        done

        echo ${thisline} >> $tmpfile
    done
done

cat $tmpfile | column --table --table-columns RUNSET,HIST,SSP,${act_col_heads}${pot_col_heads} -s ": "

#rm $tmpfile

exit 0
