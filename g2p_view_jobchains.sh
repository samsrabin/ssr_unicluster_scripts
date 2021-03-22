#!/bin/bash
set -e

testing=0
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


if [[ $testing -eq 0 ]]; then
	jobs=$(squeue -o "%P %i %j %T %r")
else
	# Note: { grep ... || true; } ensures that no error occurs if grep finds no matches
	jobs=$(squeue -o "%P %i %j %T %r" | { grep "dev_sin" || true; })
fi

#function string_contains {
#	result=0
#	if [[ $1 == *"${2}"* ]]; then
#		result=1
#	fi
#	echo $result
#}

function was_canceled {
	jobnum=$1
	sacct_result="$(sacct -n -j $jobnum)"
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
		echo "homedir_rel not found: ${homedir_rel}"
		exit 14
	fi
	if [[ $testing -eq 0 ]]; then 
		workdir=$(realpath "${homedir_rel}" | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
	else
		workdir=$(realpath $(echo "${homedir_rel}" | sed "s@/@_test/@") | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
	fi

	# workdir does NOT exist
	if [[ ! -d "${workdir}" ]]; then
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

				# If no run was started in this chain, then say so
				if [[ ${latest_job} -lt ${latest_actual_job} ]]; then
					symbol="${symbol_norun}"

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
					# Otherwise...
					else
						# If all cells completed with "Finished" message, that's great!
						nprocs=$(ls -d run* | wc -l)
						if [[ ! -e "${file_stdout}" ]]; then
							>&2 echo "${symbol_unknown} stdout file not found: ${workdir_short}/${file_stdout}"
							symbol="${symbol_unknown}"
						else
							nfinished=$(grep "Finished" ${file_stdout} | wc -l )
				         nunfinished=$((nprocs - nfinished))
							if [[ $nprocs == $nfinished ]]; then
								symbol="${symbol_ok}"
			
							# If not, was job canceled?
							elif [[ $(tail -n 100 ${file_stdout} | grep "State: CANCELLED" | wc -l) -ne 0 ]]; then
								symbol="${symbol_canceled_manual}"
			
							# Otherwise, assume run failed.
							else
								symbol="${symbol_failed}"
							fi
						fi # Does stdout file exist?
					fi # Was it canceled before beginning?
				fi # Was a run started in this chain?
	
			# JOBFIN
			else
				latest_job=$(grep "job_finish" latest_submitted_jobs.log | awk 'END {print $NF}')
				# If no run was started in this chain, then say so
				if [[ ${latest_job} -lt ${latest_actual_job} ]]; then
					symbol="${symbol_norun}"

				# Otherwise, check if simulation began
				else
					file_stdout="job_finish.${latest_job}.log"
					if [[ ! -e "${file_stdout}" ]]; then
						was_it_canceled=$(was_canceled ${latest_job})
						if [[ ${was_it_canceled} -lt 0 ]]; then
							symbol="${symbol_unknown2}"
						elif [[ ${was_it_canceled} -eq 0 ]]; then
							symbol="${symbol_unknown}"
						else
							symbol="${symbol_canceled_manual}"
						fi
						>&2 echo "${symbol_unknown} stdout file not found: ${workdir_short}/${file_stdout}"
						symbol="${symbol_unknown}"
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

cd /home/kit/imk-ifu/lr8247/g2p/runs/remap11

tmpfile=.tmp.g2p_view_jobchains.$(date +%N)
touch $tmpfile

dirlist=$(ls | grep -v "calibration\|test")
pot_col_heads=""
for d in ${dirlist}; do
	islast_act=0

	# If this directory doesn't even have a working directory set up, you can skip
	thischain_workdir=$(echo $d | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
	if [[ ${testing} -eq 1 ]]; then
		thischain_workdir="${thischain_workdir}_test"
	fi
	if [[ ! -d ${thischain_workdir} ]]; then
		continue
	fi

	# Get short name for this chain
	thischain_name="$(g2p_chain_shortname.sh ${d})"

	actdir="${d}/actual"
	if [[ ! -d "${actdir}" ]]; then
		echo "actdir not found: ${PWD}/${actdir})"
		exit 13
	fi
	ssp_list=$(ls -d "${actdir}"/ssp* | sed "s@${actdir}/@@g") 
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
			echo "potential-run directory not found: ${PWD}/${potdir}"
			exit 11
		fi
		if [[ "${pot_col_heads}" == "" ]]; then
			pot_col_heads="$(echo $(ls "${potdir}") | sed "s/ /,/g")"
			pot_col_heads="$(echo ${pot_col_heads} | sed "s/,20/,/g" | sed "s/-20/-/g")"
		fi

		# Check historical period, if necessary
		if [[ $s -eq 1 ]]; then
			homedir_rel="${d}/actual/hist"
			thisline="${thischain_name} "
			check_jobs ${thischain_name}_hist
		else
			thisline=" :"
		fi

		# Check future-actual period
		homedir_rel="${d}/actual/${ssp}"
		thisline="${thisline} ${ssp}"
		check_jobs ${thischain_name}_${ssp}_
		if [[ ${latest_job} -gt ${latest_actual_job} ]]; then
			latest_actual_job=${latest_job}
		fi

		# Check potential periods
		pot_list=$(ls "${potdir}" | cut -d' ' -f1-2)
		for pot in ${pot_list}; do
			homedir_rel="${d}/potential/${ssp}/${pot}"
			check_jobs ${thischain_name}_${pot}
		done

	done
	echo ${thisline} >> $tmpfile
done

cat $tmpfile | column --table --table-columns RUNSET,HIST,SSP,ACT,${pot_col_heads} -s ": "

#rm $tmpfile

exit 0
