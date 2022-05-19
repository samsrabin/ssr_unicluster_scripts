#!/bin/bash
set -e

###################
# Process input arguments
###################


#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="lsf_setup_potential_loop.sh"
#Declare the number of mandatory args
margs=3

# Common functions - BEGIN
function example {
echo -e "example: $script ssp126 2015 2089\n"
}

function usage {
echo " "
echo -e "usage: $script \$thisSSP \$future_y1 \$future_yN\n"
}

function help {
usage
echo -e "OPTIONAL:"
}

# Ensures that the number of passed args are at least equals
# to the declared number of mandatory args.
# It also handles the special case of the -h or --help arg.
function margs_precheck {
if [ $2 ] && [ $1 -lt $margs ]; then
   if [ $2 == "--help" ] || [ $2 == "-h" ]; then
      help
      exit
   else
      usage
      example
      exit 1 # error
   fi
fi
}

# Ensures that all the mandatory args are not empty
function margs_check {
if [ $# -lt $margs ]; then
   usage
   example
   exit 1 # error
fi
}
# Common functions - END

# SSR: Process positional arguments
# Which SSP?
if [[ "$1" == "" ]]; then
    echo "lsf_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
    exit 1
fi
thisSSP=$1
shift
# Years of the future period
if [[ "$1" == "" ]]; then
    echo "lsf_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
    exit 1
fi
future_y1=$1
shift
if [[ "$1" == "" ]]; then
    echo "lsf_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
    exit 1
fi
future_yN=$1
shift


# Set default values for non-positional arguments
# (none)

while [ "$1" != "" ];
do
   case $1 in
      -h   | --help )        help
         exit
         ;;
      *)
         echo "$script: illegal option $1"
         usage
         example
         exit 1 # error
         ;;
   esac
   shift
done

# How many years are we discarding at the beginning of the potential run?
if [[ ${Nyears_getready} == "" ]]; then
    Nyears_getready=5
fi
# How many years are we averaging over at the end of the potential run?
if [[ ${Nyears_pot} == "" ]]; then
    Nyears_pot=5
fi


###################
# Setup
###################

# How long is each potential yield run?
Nyears=$((Nyears_getready + Nyears_pot))

# Get list of beginning years
y1_list="${list_pot_y1_hist} ${list_pot_y1_future}"


###################
# Loop through periods
###################

if [[ "${topinsfile}" != "" && "${gridlist}" != "" && "${inputmodule}" != "" && "${nproc}" != "" && "${arch}" != "" && "${walltime_pot}" != "" && "${prefix}" != "" ]]; then
    actually_setup=1
else
#    echo topinsfile $topinsfile
#    echo gridlist $gridlist
#    echo inputmodule $inputmodule
#    echo nproc $nproc
#    echo arch $arch
#    echo walltime_pot $walltime_pot
#    echo prefix $prefix
    actually_setup=0
fi
for y1 in ${y1_list}; do

    # Does this run include the ssp period?
    yN=$((y1 + Nyears - 1))
    if [[ ${yN} -gt ${future_yN} ]]; then
        yN=${future_yN}
    fi
    if [[ ${yN} -gt  ${hist_yN} ]]; then
        incl_future=1
    else
        incl_future=0
    fi

    # Get dirname
    first_plut_year=$((y1+Nyears_getready))
    thisdir=${first_plut_year}pot_${y1}-${yN}
    if [[ ${incl_future} -eq 1 ]]; then
        mkdir -p "${thisSSP}"
        thisdir="${thisSSP}/${thisdir}"
    else
        mkdir -p "hist"
        thisdir="hist/${thisdir}"
    fi

    if [[ ${actually_setup} -eq 0 ]]; then
        echo "${thisdir}..."
    else
        echo " "
        echo " "
        echo "${thisdir}..."
        echo " "
    fi

    # Archive existing directory, if needed
    if [[ -d "${thisdir}" ]]; then
        this_archive="${thisdir}.$(date "+%Y-%m-%d-%H%M%S").tar"
#        echo "Archiving existing $(pwd)/${thisdir} as ${this_archive}"
        tar -cf "${this_archive}" "${thisdir}"
        rm -rf "${thisdir}"
    fi

    # Copy and fill template runDir
    cp -a ../template "${thisdir}"
    pushdq "${thisdir}"
    sed -i "s/UUUU/${yN}/" main.ins    # lasthistyear
    # restarting
    sed -i "s/^\!restart_year VVVV/restart_year ${y1}/g" main.ins
    sed -i "s/VVVV/${y1}/" main.ins    # restart_year
    sed -i "s/firstoutyear 1850/firstoutyear ${y1}/" main.ins    # firstoutyear
    sed -i "s/restart 0/restart 1/g" main.ins
    # saving state
    sed -i "s/WWWW/\"${future_y1}\"/" main.ins    # save_years
    if [[ ${y1} -ge ${future_y1} ]]; then
        sed -i "s/save_state 1/save_state 0/g" main.ins
    fi
    # land use file
    sed -i "s/XXXX/${last_LUyear_past}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
    sed -i "s/YYYY/${last_LUyear_all}/" landcover.ins    # XXXXpast_YYYYall_LU.txt
    # outputs
    sed -i "s/do_plut 0/do_plut 1/g" landcover.ins
    sed -i "s/ZZZZ/${first_plut_year}/" landcover.ins    # first_plut_year
    popdq
    mkdir -p ${thisdir}

    pushd ${thisdir} 1>/dev/null
    
    # Copy over template script
    postproc_template="$HOME/scripts/lsf_postproc.template.sh"
    if [[ ! -f ${postproc_template} ]]; then
       echo "postproc_template file not found: ${postproc_template}"
       exit 1
    fi
    cp ${postproc_template} postproc.sh
    # Replace placeholder(s)
    sed -i "s@DIRFORPLUM@${dirForPLUM}@g" postproc.sh

    # Set up dependency (or not)
    dependency=""
    if [[ "${submit}" != "" ]]; then
        if [[ $((y1-1)) -le ${hist_yN} ]]; then
            thisPeriod="hist"
        else
            thisPeriod="${thisSSP}"
        fi
        dependency_name="act-${thisPeriod}"
        r=-1
        for this_jobname in ${arr_job_name[@]}; do
            r=$((r+1))
            if [[ "${this_jobname}" == "${dependency_name}" ]]; then
                dependency="-d ${arr_job_num[r]} --dependency-name ${dependency_name}"
                break
            fi
        done
    fi
    
    # Actually set up and even submit, if being called from within setup_all.sh
    if [[ ${actually_setup} -eq 1 ]]; then
        do_setup ${walltime_pot} ${firstoutyear} ${yN}

        arr_job_name+=("${thisdir}")
        if [[ "${submit}" != "" ]]; then
            arr_job_num+=($(get_latest_run))
        fi
        arr_y1+=(${y1})
        arr_yN+=(${yN})
    fi

    popd 1>/dev/null

done