#!/bin/bash
set -e

###################
# Process input arguments
###################


#############################################################################################
# Function-parsing code from https://gist.github.com/neatshell/5283811

script="g2p_setup_potential_loop.sh"
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
	echo "g2p_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
	exit 1
fi
thisSSP=$1
shift
# Years of the future period
if [[ "$1" == "" ]]; then
	echo "g2p_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
	exit 1
fi
future_y1=$1
shift
if [[ "$1" == "" ]]; then
	echo "g2p_setup_potential_loop.sh: You must provide thisSSP, future_y1, and future_yN"
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
y1_list=$(seq ${firstpotyear} $Nyears_pot $((future_yN - Nyears)))

###################
# Loop through periods
###################

if [[ "${topinsfile}" != "" && "${gridlist}" != "" && "${inputmodule}" != "" && "${nproc}" != "" && "${arch}" != "" && "${walltime_pot}" != "" && "${prefix}" != "" ]]; then
	actually_setup=1
else
#	echo topinsfile $topinsfile
#	echo gridlist $gridlist
#	echo inputmodule $inputmodule
#	echo nproc $nproc
#	echo arch $arch
#	echo walltime_pot $walltime_pot
#	echo prefix $prefix
	actually_setup=0
fi
for y1 in ${y1_list}; do

	# Get dirname
	yN=$((y1 + Nyears - 1))
	thisdir=${thisSSP}/${y1}-${yN}
	if [[ ${actually_setup} -eq 0 ]]; then
		echo "${thisdir}..."
	else
		echo " "
		echo " "
		echo "${thisdir}..."
		echo " "
	fi
	
	# Make directory, if needed
	mkdir -p ${thisdir}
	
	# Copy actual future run to this directory
	cp -r ../actual/${thisSSP}/* ${thisdir}/
	
	pushd ${thisdir} 1>/dev/null
	
	# Disable state saving
	sed -i "s/save_state 1/save_state 0/g" main.ins
	
	# Set first year of this run
	restart_year_txt=$(grep -oE "restart_year\s+[0-9]+" main.ins)
	sed -i "s/${restart_year_txt}/restart_year ${y1}/g" main.ins
	
	# Set lasthistyear to year AFTER last year we care about, because
	# file_plantyear_st only saves year Y at the end of year Y+1
	lasthistyear_txt=$(grep -oE "lasthistyear\s+[0-9]+" main.ins)
	sed -i "s/${lasthistyear_txt}/lasthistyear $((yN + 1))/g" main.ins
	
	# Tell LPJ-GUESS to use do_potyield (and rename this ins-file section)
	sed -i "s/! SSR: future/! SSR: potential yields\ndo_potyield 1/g" main.ins
	
	# Make LPJ-GUESS use PFT-specific N fertilization instead of input file
	sed -i "s/^param \"file_Nfert\".*/\param \"file_Nfert\" (str \"\")/g" crop.ins
	
	# Don't simulate natural land
	file_lu=$(get_param.sh landcover.ins file_lu)
	[[ "${file_lu}" == "" ]] && exit 1
	sed -i "s@${file_lu}@${file_lu/someOfEachCrop/justCPB_1yr}@" landcover.ins

	# Set do_potyield to 1 and remove file_lucrop, which is thus unnecessary.
	sed -i -E 's@param "file_lucrop".*$@param "file_lucrop" (str "")\ndo_potyield 1@g' landcover.ins

	# Don't use N deposition
	sed -i -E "s@param\s+(\"file_mN[HO][xy]\S\S\Sdep\")\s+\(str\s+(\".+\")\)@param \1 \(str \"\"\)@g" main.ins

	# Only save the years needed
	firstoutyear=$((yN - Nyears_pot + 1))
	sed -i -E "s@firstoutyear\s+[0-9]+@firstoutyear ${firstoutyear}@" main.ins

	# Copy over template script
   postproc_template="$HOME/scripts/g2p_postproc.template.pot.sh"
   if [[ ! -f ${postproc_template} ]]; then
      echo "postproc_template file not found: ${postproc_template}"
      exit 1
   fi
   cp ${postproc_template} postproc.sh
   # Replace years
   sed -i "s/OUTY1/${firstoutyear}/g" postproc.sh
   sed -i "s/OUTYN/${yN}/g" postproc.sh
   # Replace croplist
   croplist=$(echo $(grep "pft" $(ls -tr crop_n_pftlist.*.ins  | tail -n 1) | sed -E 's/pft\s+"([^".]+)"\s*\(/\1/g' | grep -v "ExtraCrop") | sed 's/ /\" \"/g')
   if [[ "${croplist}" == "" ]]; then
      echo "Unable to parse croplist; failing"
      exit 1
   fi
	sed -i "s/CROPLIST/${croplist}/g" postproc.sh
   # Replace Nfertlist
   nfertlist=$(echo $(grep "st " crop_n_stlist.*.ins | sed "s/C[34]//g" | grep -oE "[0-9]+\"" | sort | uniq | sed 's/"//') | sed 's/ /\" \"/g')
   if [[ "${nfertlist}" == "" ]]; then
      echo "Unable to parse nfertlist; failing"
      exit 1
   fi
   sed -i "s/NFERTLIST/${nfertlist}/g" postproc.sh
	
#	# Replace shell scripts with potential-yield versions
#	rm *.sh
#	cp ../../setup*.sh .

	# Actually set up and even submit, if being called from within setup_all.sh
	if [[ ${actually_setup} -eq 1 ]]; then
		do_setup ${walltime_pot} ${firstoutyear} ${yN}
	fi

	popd 1>/dev/null

done

exit 0
