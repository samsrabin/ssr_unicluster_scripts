#!/bin/bash
set -e

cd /home/kit/imk-ifu/xg4606/GGCMI/runs_2022-09/isimip3b

gcm_long=$1
if [[ "${gcm_long}" == "" ]]; then
	echo "You must provide gcm_long (e.g., MRI-ESM2-0)"
	exit 1
elif [[ ! -d "/pfs/work7/workspace/scratch/xg4606-isimip3_climate/climate3b/historical/${gcm_long}-lpjg" ]]; then
	echo "${gcm_long} does not appear to be a valid GCM"
	exit 1
fi

# Get lowercase long name
gcm_long_lower=$(echo $gcm_long | tr '[:upper:]' '[:lower:]')
if [[ "${gcm_long_lower}" == "${gcm_long}" ]]; then
	echo "Error finding gcm_long_lower"
	exit 1
fi

# Get short name
if [[ "${gcm_long}" == "GFDL-ESM4" ]]; then
	gcm_short="gfdl"
elif [[ "${gcm_long}" == "IPSL-CM6A-LR" ]]; then
	gcm_short="ipsl"
elif [[ "${gcm_long}" == "MPI-ESM1-2-HR" ]]; then
	gcm_short="mpi"
elif [[ "${gcm_long}" == "MRI-ESM2-0" ]]; then
	gcm_short="mri"
elif [[ "${gcm_long}" == "UKESM1-0-LL" ]]; then
	gcm_short="ukesm"
else
	echo "${gcm_long} can't be parsed into gcm_short"
	exit 1
fi

# Get ensemble member
ensemble_member=$(ls /pfs/work7/workspace/scratch/xg4606-isimip3_climate/climate3b/historical/${gcm_long}-lpjg/*_tas_* | grep -oE "r[0-9]i[0-9]p[0-9]f[0-9]")
if [[ "${ensemble_member}" == "" ]]; then
	echo "Error finding ensemble_member"
	exit 1
fi

# Get tiny name
gcm_tiny=$(echo ${gcm_long_lower} | cut -c1-2)
if [[ "${gcm_tiny}" == "" ]]; then
	echo "Error finding gcm_tiny"
	exit 1
fi

echo "New GCM info:"
echo "   gcm_long $gcm_long"
echo "   gcm_long_lower $gcm_long_lower"
echo "   gcm_short $gcm_short"
echo "   gcm_tiny $gcm_tiny"
echo "   ensemble_member $ensemble_member"

# Original GCM info
gcm0_long="UKESM1-0-LL"
gcm0_long_lower="ukesm1-0-ll"
gcm0_short="ukesm"
gcm0_tiny="uk"
gcm0_ensemble_member="r1i1p1f2"

if [[ "${gcm0_long}" == "${gcm_long}" ]]; then
	echo "Source and destination GCMs are both $gcm_long; aborting."
	exit 0
fi

for d in $(ls -d ${gcm0_short}*/ | sed "s/${gcm0_short}_//"); do
	newdir=${gcm_short}_$d
	if [[ -d ${newdir} ]]; then
		rm -rf ${newdir}
	fi
	cp -r ${gcm0_short}_$d ${newdir}
	cd ${newdir}
	echo "Duplicating into ${newdir}..."

#	echo "   gcm_long in main.ins"
	for f in $(find . -name main.ins); do
#		echo "      ${newdir}/$f"
		md5sum_before=$(md5sum $f | cut -d " " -f1)
		sed -i "s/${gcm0_long}/${gcm_long}/g" $f
		md5sum_after=$(md5sum $f | cut -d " " -f1)
		if [[ ${md5sum_before} == ${md5sum_after} ]]; then
			echo "Error changing ${newdir}/$f from ${gcm0_long} to ${gcm_long}"
			exit 1
		fi
	done

#	echo "   gcm_long_lower in main.ins"
	for f in $(find . -name main.ins); do
#		echo "      ${newdir}/$f"
		md5sum_before=$(md5sum $f | cut -d " " -f1)
		sed -i "s/${gcm0_long_lower}/${gcm_long_lower}/g" $f
		md5sum_after=$(md5sum $f | cut -d " " -f1)
		if [[ ${md5sum_before} == ${md5sum_after} ]]; then
			echo "Error changing ${newdir}/$f from ${gcm0_long_lower} to ${gcm_long_lower}"
			exit 1
		fi
	done

	if [[ "${gcm0_ensemble_member}" != "${ensemble_member}" ]]; then
#		echo "   ensemble_member in main.ins"
		for f in $(find . -name main.ins); do
#			echo "      ${newdir}/$f"
			md5sum_before=$(md5sum $f | cut -d " " -f1)
			sed -i "s/${gcm0_ensemble_member}/${ensemble_member}/g" $f
			md5sum_after=$(md5sum $f | cut -d " " -f1)
			if [[ ${md5sum_before} == ${md5sum_after} ]]; then
				echo "Error changing ${newdir}/$f ensemble member from ${gcm0_long}'s to ${gcm_long}'s"
				exit 1
			fi
		done
	fi

#	echo "   gcm_short in shell scripts"
	for f in $(find . -name *sh); do 
		has_linked_state=$(grep " \-L " $f | wc -l)
		if [[ $has_linked_state -eq 0 ]]; then
			continue
		fi
#		echo "      ${newdir}/$f"
		md5sum_before=$(md5sum $f | cut -d " " -f1)
		sed -i "s/${gcm0_short}/${gcm_short}/g" $f
		md5sum_after=$(md5sum $f | cut -d " " -f1)
		if [[ ${md5sum_before} == ${md5sum_after} ]]; then
			echo "Error changing ${newdir}/$f from ${gcm0_short} to ${gcm_short}"
			exit 1
		fi
	done

#	echo "   gcm_tiny in shell scripts"
	for f in $(find . -name *sh); do 
		has_job_name=$(grep " \-p " $f | wc -l)
		if [[ $has_job_name -eq 0 ]]; then
			continue
		fi
#		echo "      ${newdir}/$f"
		md5sum_before=$(md5sum $f | cut -d " " -f1)
		sed -i "s/_${gcm0_tiny}_/_${gcm_tiny}_/g" $f
		md5sum_after=$(md5sum $f | cut -d " " -f1)
		if [[ ${md5sum_before} == ${md5sum_after} ]]; then
			echo "Error changing gcm_tiny in ${newdir}/$f from ${gcm0_tiny} to ${gcm_tiny}"
			exit 1
		fi
	done

	cd ..

done

exit 0
