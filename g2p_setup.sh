#!/bin/bash
set -e

prefix="g2p_uk_a2d"
realinsfile="main.ins"
testinsfile="main_test2.ins"
inputmodule="cfx"
nproc=160
arch="landsymm-dev-crops"
walltime_hist="72:00:00"
walltime_fut="72:00:00"
walltime_pot="8:00:00"
future_y1=2015
future_yN=2089 # Because last year of emulator output is 2084
Nyears_getready=5
Nyears_pot=5

#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="g2p_setup.sh"
function usage {
echo " "
echo -e "usage: $script [-t]\n"
}

# Set default values for non-positional arguments
istest=0
submit=""

# Args while-loop
while [ "$1" != "" ];
do
   case $1 in
      -s  | --submit)
         submit="--submit"
         ;;
      -t  | --test)
         istest=1
         ;;
      *)
         echo "$script: illegal option $1"
         usage
         exit 1 # error
         ;;
   esac
   shift
done

#############################################################################################

# Process test vs. real thing
if [[ ${istest} -eq 1 ]]; then
   topinsfile=${testinsfile}
   walltime_hist="30:00"
   walltime_fut="30:00"
   walltime_pot="30:00"
   nproc=1
   ppfudev="--no_fu --dev"
else
   topinsfile=${realinsfile}
   ppfudev="--no_pp"
fi

# Set up function for getting ins files
function get_ins_files {
insfiles=$(ls *ins | grep -v "main")
if [[ ${istest} -eq 1 ]]; then
   insfiles="${realinsfile} ${insfiles}"
fi
echo $insfiles
}

# Set up function for getting absolute state path
function get_state_path {
topdir=$PWD
state_path_absolute=$(echo $topdir | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@" | sed "s@/$topdir@@")/states
if [[ ${thisSSP} != "" ]]; then
   state_path_thisSSP="${state_path_absolute}"
	restart_year=$(get_param.sh ${topinsfile} restart_year)
	lasthistyear=$(get_param.sh ${topinsfile} lasthistyear)

	state_path_hist=$(echo ${state_path_thisSSP} | sed "s@/${thisSSP}/@/hist/@")
	topdir_hist=$(echo $PWD | sed "s@/${thisSSP}@/hist@")
	link_arguments=""
	for y in $(get_param.sh ${topdir_hist}/${topinsfile} "save_years"); do
		if [[ ${y} -ge $((restart_year - 2*Nyears_pot))  && ${y} -le ${lasthistyear} ]]; then
			link_arguments="${link_arguments} -L ${state_path_hist}/$y"
		fi
	done
   state_path_absolute="${state_path_thisSSP} ${link_arguments}"
fi
echo "${state_path_absolute}"
}

# Set up function to set up
function do_setup {
   walltime=$1
   shift
   if [[ "${walltime}" == "" ]]; then
      echo "You must provide walltime to do_setup()"
      exit 1
   fi
   if [[ ! -e "${gridlist}" ]]; then
      echo "Gridlist file ${gridlist} not found"
      exit 1
   fi
   if [[ "${state_path}" == "" ]]; then
      state_path=$(get_state_path)
   fi
   g2p_setup_1run.sh ${topinsfile} "$(get_ins_files)" ${gridlist} ${inputmodule} ${nproc} ${arch} ${walltime} -p "${prefix}" -s ${state_path} ${submit} ${ppfudev} ${dependency}
}

mkdir -p potential

#############################################################################################

# Set up "actual" historical run (no dependency)
dependency=""
thisSSP=""
echo "###################"
echo "### actual/hist ###"
echo "###################"
set " "
cd actual/hist

# Get gridlist
gridlist=$(get_param.sh ${topinsfile} "file_gridlist")
if [[ "${gridlist}" == "" ]]; then
   echo "Unable to parse gridlist from ${topinsfile} and its dependencies"
   exit 1
fi

state_path=""
do_setup ${walltime_hist}
cd ..
echo " "
echo " "

# All other runs will have dependency
dependency="-d LATEST"

# Set up SSP actual and potential runs
for thisSSP in $(ls -d ssp*); do
   echo "#####################"
   echo "### actual/${thisSSP} ###"
   echo "#####################"
   set " "
   cd ${thisSSP}
   state_path=""
   do_setup ${walltime_fut}
   cd ..
   echo " "
   echo " "

   echo "#########################"
   echo "### potential/${thisSSP} ###"
   echo "#########################"
   set " "
   cd ../potential
	state_path=$(echo $state_path | sed -E "s/ -L.*//")
   . g2p_setup_potential_loop.sh ${thisSSP} ${future_y1} ${future_yN}
   cd ../actual
   echo " "
   echo " "
done


exit 0
