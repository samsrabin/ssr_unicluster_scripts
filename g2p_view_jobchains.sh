#!/bin/bash
set -e

testing=1
symbol_noworkdir="--"
symbol_pend_depend="👀"
symbol_pend_other="⏳"
symbol_running="🏃"
symbol_ok="✅"
symbol_canceled="🙅"
symbol_failed="❌"

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

if [[ $testing -eq 0 ]]; then
	jobs=$(squeue -o "%P %i %j %T %r")
else
	jobs=$(squeue -o "%P %i %j %T %r" | { grep "dev_sin" || true; })
fi
#if [[ "${jobs}" == "" ]]; then
#	echo "No jobs. Deal with this!"
#	exit 6
#fi

#function string_contains {
#	result=0
#	if [[ $1 == *"${2}"* ]]; then
#		result=1
#	fi
#	echo $result
#}

function get_symbol {
	matching_jobs=$(echo "${jobs}" | { grep -E "\s${thepattern}" || true; })
   if [[ "${matching_jobs}" == "" ]]; then

		# First, change to working directory
		if [[ $testing -eq 0 ]]; then 
			workdir=$(realpath "${homedir_rel}" | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
		else
			workdir=$(realpath $(echo "${homedir_rel}" | sed "s@/@_test/@") | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
		fi
		if [[ ! -d "${workdir}" ]]; then
			symbol="${symbol_noworkdir}"
#			>&2 echo "Error finding workdir"
#			>&2 echo "homedir_rel = ${homedir_rel}"
#			>&2 echo "workdir = ${workdir}"
#			exit 3
		else
			pushd "${workdir}"
	
			# SIMULATION
			if [[ "${thepattern:0:6}" != "jobfin" ]]; then
				# Check if simulation began
				latest_sim=$(grep "LPJ-GUESS run" latest_submitted_jobs.log | awk 'END {print $NF}')
				# If not, assume it was canceled before beginning.
		      if [[ ! -e guess_x.o${latest_sim} ]]; then
					symbol="${symbol_canceled}"
				# Otherwise...
				else
					# If all cells completed with "Finished" message, that's great!
					nprocs=$(ls -d run* | wc -l)
					file_stdout="guess_x.o${latest_sim}"
					nfinished=$(grep "Finished" ${file_stdout} | wc -l )
		         nunfinished=$((nprocs - nfinished))
					if [[ $nprocs == $nfinished ]]; then
						symbol="${symbol_ok}"
	
					# If not, was job canceled?
					elif [[ $(tail -n 100 ${file_stdout} | grep "State: CANCELLED" | wc -l) -ne 0 ]]; then
						symbol="${symbol_canceled}"
	
					# Otherwise, assume run failed.
					else
						symbol="${symbol_failed}"
					fi
				fi
	
			# JOBFIN
			else
				file_stdout="job_finish.log"
	
				# Completed successfully?
				if [[ $(tail -n 20 ${file_stdout} | grep "All done\!" | wc -l) -gt 0 ]]; then
					symbol="${symbol_ok}"
	
	         # If not, was job canceled?
	         elif [[ $(tail -n 100 ${file_stdout} | grep "State: CANCELLED" | wc -l) -ne 0 ]]; then
	            symbol="${symbol_canceled}"
	
	         # Otherwise, assume run failed.
	         else
	            symbol="${symbol_failed}"
	         fi
				
			fi
	
	
			popd
		fi
	else
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
		fi
	fi

	echo $symbol
}

function check_jobs {

	# Model run
	# Note: { grep ... || true; } ensures that no error occurs if grep finds no matches
	thepattern="${1}"
	thisline="${thisline} $(get_symbol "${thisstatus}")"
#	echo $thisline
	
	# Postprocessing
	thepattern="jobfin_${thepattern}"
   thisline="${thisline}/$(get_symbol "${thisstatus}")"
#	echo $thisline

}

cd /home/kit/imk-ifu/lr8247/g2p/runs/remap11

tmpfile=.tmp.g2p_view_jobchains.$(date +%N)
touch $tmpfile

echo "$jobs"

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
	cli=$(echo $d | cut -d'_' -f2)
	soc=$(echo $d | cut -d'_' -f3)
	co2=$(echo $d | cut -d'_' -f4)
	thischain_name="g2p_${d:0:2}_${cli:0:1}${soc:0:1}${co2:0:1}"

	ssp_list=$(ls -d ${d}/actual/ssp* | sed "s@${d}/actual/@@")
	s=0
	for ssp in ${ssp_list}; do
		s=$((s+1))
		if [[ ${ssp} == $(echo ${ssp_list} | grep -oE '[^ ]+$') ]]; then
			islast_act=1
		else
			islast_act=0
		fi

		# Get potential column headers, if necessary
		if [[ "${pot_col_heads}" == "" ]]; then
			pot_col_heads="$(echo $(ls ${d}/potential/${ssp}/) | sed "s/ /,/g")"
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

		# Check potential periods
		pot_list=$(ls ${d}/potential/${ssp}/ | cut -d' ' -f1-2)
		for pot in ${pot_list}; do
			homedir_rel="${d}/potential/${ssp}/${pot}"
			check_jobs ${thischain_name}_${ssp}pot_${pot}
		done

	done
	echo ${thisline} >> $tmpfile
done

cat $tmpfile | column --table --table-columns RUNSET,HIST,SSP,ACT,${pot_col_heads} -s ": "

#rm $tmpfile

exit 0
