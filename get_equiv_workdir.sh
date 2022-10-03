
cd "$1"

if [[ "${WORK}" == "" ]]; then
   >&2 echo "\$WORK undefined"
   exit 1
elif [[ ! -e "${WORK}" ]]; then
   >&2 echo "\$WORK not found: $WORK"
   exit 1
fi
equiv_workdir=$(pwd | sed "s@/pfs/data5@@" | sed "s@$HOME@$WORK@")
if [[ ${testing} -eq 1 ]]; then
    equiv_workdir="${equiv_workdir}_test"
fi
echo ${equiv_workdir}

