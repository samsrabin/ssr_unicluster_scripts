
# Set up function for getting ins files
function get_ins_files {
    if [[ ${do_fu_only} -eq 1 ]]; then
        insfiles="xxx"
    else
        insfiles=$(ls *ins | grep -v "main")
        if [[ ${istest} -eq 1 ]]; then
            insfiles="${realinsfile} ${insfiles}"
        fi
    fi
    echo $insfiles
}

# Set up function for getting absolute state path
function get_state_path {
    if [[ ${thisSSP} != "" ]]; then
        if [[ "${state_path_thisSSP}" == "" ]]; then
            echo "get_state_path(): state_path_thisSSP is unspecified" >&2
            exit 1
        fi
        state_path_absolute="-s ${state_path_thisSSP}"
    fi
    echo "${state_path_absolute}"
}

# Set up function to set up
function do_setup {
    walltime=$1
    ispot=$2
    if [[ "${walltime}" == "" ]]; then
        echo "You must provide walltime to do_setup()"
        exit 1
    fi
    if [[ ${do_fu_only} -eq 1 ]]; then
        gridlist="xxx"
    elif [[ ! -e "${gridlist}" ]]; then
        echo "Gridlist file ${gridlist} not found"
        exit 1
    fi
    if [[ "${state_path}" == "" ]]; then
        echo "Make sure state_path is defined before calling do_setup"
        exit 1
    elif [[ "${state_path}" != "-s "* && "${state_path}" != "--state-path-absolute "* ]]; then
        state_path="-s ${state_path}"
    fi

    if [[ "${dependency}" != "" ]]; then
        will_depend_text="Will depend on job(s)"
        for j in $(echo ${dependency} | grep -oE " [0-9]+"); do
            jname=""
            jj=-1
            for n in ${arr_job_num[@]}; do
                jj=$((jj + 1))
                if [[ ${n} -eq ${j} ]]; then
                    jname="${arr_job_name[jj]}"
                    break
                fi
            done
            if [[ "${jname}" == "" ]]; then
                jname=${j}
            fi
            will_depend_text+=" ${jname}"
        done
        echo ${will_depend_text}
    fi

    rc_setup_1run.sh ${topinsfile} "$(get_ins_files)" ${gridlist} ${inputmodule} ${nproc} ${arch} ${walltime} -p "${this_prefix}" ${state_path} ${submit} ${ppfudev} ${dependency} ${reservation} --lpjg_topdir "${lpjg_topdir}" ${mem_spec} ${delete_state_arg}

}

pushdq () {
    echo pwd $PWD
    command pushd "$@" > /dev/null
}

popdq () {
    command popd "$@" > /dev/null
}

function get_latest_run {
    grep "LPJ-GUESS" ${HOME}/submitted_jobs.log | tail -n 1 | sed "s/LPJ-GUESS run: //"
}
