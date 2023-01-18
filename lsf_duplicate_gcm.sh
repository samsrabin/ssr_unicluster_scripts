#!/bin/bash
set -e

cd /home/kit/imk-ifu/xg4606/landsymm/runs-forestonly/runs-2022-10

gcm_in="$1"

# SSR 2023-01-17: The first runs I did for Bart used this. They probably shouldn't.
echo "WARNING: USING OLD, ARTIFACT-FILLED CLIMATE"
isimip3_climate_dir="$(ws_find isimip3_climate)"

. gp3_get_gcm_info.sh

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
    mkdir -p ${newdir}/template
	cp -a ${gcm0_short}_$d/template/* ${newdir}/template/
	cd ${newdir}

    echo "Copying template into ${newdir}..."

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
    pattern="${gcm0_short}"
    for f in $(grep -l "${pattern}" $(find . -name "*sh")); do
		has_linked_state=$(grep " \-L " $f | wc -l)
		if [[ $has_linked_state -eq 0 ]]; then
			continue
		fi
#		echo "      ${newdir}/$f"
		md5sum_before=$(md5sum $f | cut -d " " -f1)
		sed -i "s/${pattern}/${gcm_short}/g" $f
		md5sum_after=$(md5sum $f | cut -d " " -f1)
		if [[ ${md5sum_before} == ${md5sum_after} ]]; then
			echo "Error changing ${newdir}/$f from ${pattern} to ${gcm_short}"
			exit 1
		fi
	done

#	echo "   gcm_tiny in shell scripts"
    pattern="_${gcm0_tiny}_"
    for f in $(grep -l "${pattern}" $(find . -name "*sh")); do
		has_job_name=$(grep " \-p " $f | wc -l)
		if [[ $has_job_name -eq 0 ]]; then
			continue
		fi
#		echo "      ${newdir}/$f"
		md5sum_before=$(md5sum $f | cut -d " " -f1)
		sed -i "s/${pattern}/_${gcm_tiny}_/g" $f
		md5sum_after=$(md5sum $f | cut -d " " -f1)
		if [[ ${md5sum_before} == ${md5sum_after} ]]; then
			echo "Error changing gcm_tiny in ${newdir}/$f from ${gcm0_tiny} to ${gcm_tiny}"
			exit 1
		fi
	done

	cd ..

done

exit 0
