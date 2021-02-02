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
thisSSP=$1
shift
# Years of the future period
future_y1=$1
shift
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
Nyears_getready=5
# How many years are we averaging over at the end of the potential run?
Nyears_pot=5

###################
# Setup
###################

# How long is each potential yield run?
Nyears=$((Nyears_getready + Nyears_pot))

# Get list of beginning years
y1_list=$(seq $((future_y1 - Nyears - Nyears_pot)) $Nyears_pot $((future_yN - Nyears)))

###################
# Loop through periods
###################

if [[ "${topinsfile}" != "" && "${gridlist}" != "" && "${inputmodule}" != "" && "${nproc}" != "" && "${arch}" != "" && "${walltime}" != "" && "${prefix}" != "" ]]; then
	actually_setup=1
else
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
	
	# Set lasthistyear
	lasthistyear_txt=$(grep -oE "lasthistyear\s+[0-9]+" main.ins)
	sed -i "s/${lasthistyear_txt}/lasthistyear ${yN}/g" main.ins
	
	# Tell LPJ-GUESS to use do_potyield (and rename this ins-file section)
	sed -i "s/! SSR: future/! SSR: potential yields\ndo_potyield 1/g" main.ins
	
	# Make LPJ-GUESS use PFT-specific N fertilization instead of input file
	sed -i "s/^param \"file_Nfert\".*/\param \"file_Nfert\" (str \"\")/g" crop.ins
	
	# Don't simulate natural land
	sed -i "s/_g2p.txt/_g2p.justCPB_1yr.txt/g" landcover.ins
	
#	# Replace shell scripts with potential-yield versions
#	rm *.sh
#	cp ../../setup*.sh .

	# Actually set up and even submit, if being called from within setup_all.sh
	if [[ ${actually_setup} -eq 1 ]]; then
		do_setup ${walltime}
	fi

	exit 1
	
	popd 1>/dev/null

done

exit 0
