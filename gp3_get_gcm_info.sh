
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

echo "GCM info:"
echo "   gcm_long $gcm_long"
echo "   gcm_long_lower $gcm_long_lower"
echo "   gcm_short $gcm_short"
echo "   gcm_tiny $gcm_tiny"
echo "   ensemble_member $ensemble_member"

