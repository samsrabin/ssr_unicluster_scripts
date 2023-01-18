# If not already provided, get input argument
if [[ "${gcm_in}" == "" ]]; then
    gcm_in="$1"
fi
if [[ "${gcm_in}" == "" ]]; then
    echo "You must specify a GCM as first argument" >&2
    exit 1
fi

# Get lowercase input name
gcm_in_orig="${gcm_in}"
gcm_in="$(echo ${gcm_in} | tr '[:upper:]' '[:lower:]')"

# Get long name
if [[ "${gcm_in}" == "g"* ]]; then
    gcm_long="GFDL-ESM4"
elif [[ "${gcm_in}" == "i"* ]]; then
    gcm_long="IPSL-CM6A-LR"
elif [[ "${gcm_in}" == "mp"* ]]; then
    gcm_long="MPI-ESM1-2-HR"
elif [[ "${gcm_in}" == "mr"* ]]; then
    gcm_long="MRI-ESM2-0"
elif [[ "${gcm_in}" == "u"* ]]; then
    gcm_long="UKESM1-0-LL"
else
    echo "GCM ${gcm_in_orig} not recognized" >&2
    exit 1
fi

# Make sure GCM data exist
if [[ "${isimip3_climate_dir}" == "" ]]; then
    isimip3_climate_dir="$2"
fi
if [[ "${isimip3_climate_dir}" == "" ]]; then
    echo "You must specify isimip3_climate_dir as second argument" >&2
    exit 1
elif [[ ! -d "${isimip3_climate_dir}" ]]; then
    echo "isimip3_climate_dir not found: ${isimip3_climate_dir}"
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
gcm_eg_tas_file="$(find "${isimip3_climate_dir}/climate3b" -type f -wholename "*/${gcm_long}-lpjg/*_tas_*" | head -n 1)"
if [[ ! -f "${gcm_eg_tas_file}" ]]; then
	echo "${gcm_long} does not appear to have any data: no example tas file found" >&2
	exit 1
fi
ensemble_member=$(echo ${gcm_eg_tas_file} | grep -oE "r[0-9]i[0-9]p[0-9]f[0-9]")
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

