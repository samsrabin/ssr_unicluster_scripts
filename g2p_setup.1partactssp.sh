#!/bin/bash
set -e

reservation="-r landsymm-project"
realinsfile="main.ins"
#testinsfile="main_test2.ins"; testnproc=1
testinsfile="main_test2x2.ins"; testnproc=2
inputmodule="cfx"
nproc=160
arch="g2p"
walltime_hist="48:00:00" # Should take around 37 hours
walltime_fut="24:00:00"  # Should take around 19 hours
walltime_pot="12:00:00"  # Should take around 10 hours
future_y1=2015
future_yN=2089 # Because last year of emulator output is 2084
Nyears_getready=5
Nyears_pot=5

firstpotyear=$((future_y1 - Nyears_getready - 2*Nyears_pot))

#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="g2p_setup.sh"
function usage {
echo " "
echo -e "usage: $script [-t]\n"
}

# Set default values for non-positional arguments
istest=0
arg_do_fu=0
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
       --fu)
         arg_do_fu=1
         ;;
      *)
         echo "$script: illegal option $1"
         usage
         exit 1 # error
         ;;
   esac
   shift
done

do_fu=0
if [[ $istest -eq 0 || $arg_do_fu -eq 1 ]]; then
	do_fu=1
fi

#############################################################################################

# Process test vs. real thing
if [[ ${istest} -eq 1 ]]; then
   topinsfile=${testinsfile}
   walltime_hist="30:00"
   walltime_fut="30:00"
   walltime_pot="30:00"
   nproc=${testnproc}
   ppfudev="--dev"
	if [[ $do_fu -eq 0 ]]; then
		ppfudev="--dev"
	else
		ppfudev="--dev --fu"
	fi
	reservation=""
else
   topinsfile=${realinsfile}
	if [[ $do_fu -eq 0 ]]; then
		ppfudev="--no_fu"
	fi
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
   if [[ "${restart_year}" == "get_param.sh_FAILED" ]]; then
      echo "get_param.sh_FAILED"
      exit 1
   fi
   lasthistyear=$(get_param.sh ${topinsfile} lasthistyear)
   if [[ "${lasthistyear}" == "get_param.sh_FAILED" ]]; then
      echo "get_param.sh_FAILED"
      exit 1
   fi

   state_path_hist=$(echo ${state_path_thisSSP} | sed "s@/${thisSSP}/@/hist/@")
   topdir_hist=$(echo $PWD | sed "s@/${thisSSP}@/hist@")
   link_arguments=""
   save_years=$(get_param.sh ${topdir_hist}/${topinsfile} "save_years")
   if [[ "${save_years}" == "get_param.sh_FAILED" ]]; then
      echo "get_param.sh_FAILED"
      exit 1
   fi
   for y in $(get_param.sh ${topdir_hist}/${topinsfile} "save_years"); do
      if [[ ${y} -ge ${firstpotyear}  && ${y} -le ${lasthistyear} ]]; then
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
		[[ "${state_path}" == "get_param.sh_FAILED" ]] && exit 1
   fi
	#croplist=$(grep "pft" $(ls -tr crop_n_pftlist.*.ins  | tail -n 1) | sed -E 's/pft\s+"([^".]+)"\s*\(/\1/g' | grep -v "ExtraCrop")
   g2p_setup_1run.sh ${topinsfile} "$(get_ins_files)" ${gridlist} ${inputmodule} ${nproc} ${arch} ${walltime} -p "${prefix}" -s ${state_path} ${submit} ${ppfudev} ${dependency} ${reservation}
}

mkdir -p potential

#############################################################################################

while [[ ! -d actual ]]; do
	cd ../
	if [[ "$PWD" == "/" ]]; then
		echo "g2p_setup.sh must be called from a (subdirectory of a) directory that has an actual/ directory"
		exit 1
	fi
done

# Get job name prefix
prefix="$(g2p_chain_shortname.sh $(basename ${PWD}) ${istest})"

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
[[ "${gridlist}" == "get_param.sh_FAILED" ]] && exit 1
if [[ "${gridlist}" == "" ]]; then
   echo "Unable to parse gridlist from ${topinsfile} and its dependencies"
   exit 1
fi

# Set up postprocessing
firstactyear=$((firstpotyear + Nyears_getready))
# Copy over template script
postproc_template="$HOME/scripts/g2p_postproc.template.act.sh"
if [[ ! -f ${postproc_template} ]]; then
   echo "postproc_template file not found: ${postproc_template}"
   exit 1
fi
cp ${postproc_template} postproc.sh
# Replace years
sed -i "s/OUTY1/${firstactyear}/g" postproc.sh
sed -i "s/OUTYN/$((future_y1 - 1))/g" postproc.sh
sed -i "s/NYEARS_POT/${Nyears_pot}/g" postproc.sh
# Set up top-level output directory
workdir=$WORK
if [[ "${workdir}" == "" ]]; then
   echo "\$WORK undefined"
   exit 1
elif [[ ! -e "${workdir}" ]]; then
   echo "\$WORK not found: $WORK"
   exit 1
fi
echo " "

state_path=""
do_setup ${walltime_hist}
cd ..
echo " "
echo " "

# Set up dirForPLUM
rundir_top=$workdir/$(pwd | sed "s@/pfs/data5/home@/home@" | sed "s@${HOME}/@@")
if [[ ${istest} -eq 1 ]]; then
	thisbasename=$(g2p_get_basename.sh)
	rundir_top=$(echo ${rundir_top} | sed "s@${thisbasename}@${thisbasename}_test@")
fi
if [[ ! -d ${rundir_top} ]]; then
	echo "rundir_top not found: ${rundir_top}"
	exit 1
fi
dirForPLUM=$(realpath ${rundir_top}/../..)/outputs/outForPLUM-$(date "+%Y-%m-%d-%H%M%S")
echo "Top-level output directory: $dirForPLUM"
echo " "
mkdir -p ${dirForPLUM}

# All other runs will have dependency
dependency="-d LATEST"

# Set up SSP actual and potential runs
for thisSSP in $(ls -d ssp*); do
   echo "#####################"
   echo "### actual/${thisSSP} ###"
   echo "#####################"
   set " "
   cd ${thisSSP}
	# Copy over template script
   postproc_template="$HOME/scripts/g2p_postproc.template.act.sh"
   if [[ ! -f ${postproc_template} ]]; then
      echo "postproc_template file not found: ${postproc_template}"
      exit 1
   fi
   cp ${postproc_template} postproc.sh
   # Replace years
   sed -i "s/OUTY1/${future_y1}/g" postproc.sh
   sed -i "s/OUTYN/${future_yN}/g" postproc.sh
   sed -i "s/NYEARS_POT/${Nyears_pot}/g" postproc.sh
	# Set up run
   state_path=""
   do_setup ${walltime_fut}

	exit 1

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
