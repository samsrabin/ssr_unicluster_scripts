#!/bin/bash
set -e

inDir="$1"
if [[ "${inDir}" == "" ]]; then
    echo "You must provide an outForPLUM directory for lsf_package_forPLUM.sh to package." >&2
    exit 1
elif [[ ! -d "${inDir}" ]]; then
    echo "Directory not found: ${inDir}" >&2
    exit 1
fi

outDir="${inDir}.reduced"
echo "Copying needed files to '${outDir}'..."
mkdir -p "${outDir}"

cd "${inDir}"
for d in *; do
    # Skip non-directories
    if [[ ! -d "${d}" ]]; then
        continue
    fi

    echo "   ${d}..."
    mkdir -p "${outDir}/${d}"
    cp -a $d/runinfo* "${outDir}/${d}/"
    cp -a $d/cflux_landsymm_sts.out.gz "${outDir}/${d}/"
    cp -a $d/landsymm_pcutW_sts.out.gz "${outDir}/${d}/"
done

echo "Making tar archive '${outDir}.tar' ..."
tar -cf "${outDir}.tar" "${outDir}"


exit 0
