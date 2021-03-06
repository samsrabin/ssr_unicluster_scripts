#!/bin/bash
set -e

insfile=$(grep -E "^\s*mpirun\s" submit.sh | grep -oE "\S+$")
gl=$(get_param.sh ${insfile} "file_gridlist")
[[ "${gl}" == "get_param.sh_FAILED" ]] && exit 1
nparts=$(ls -d run*/ | grep -oE "[0-9]+" | sort -g | tail -n 1)

stdoutfile=$(ls -tr guess_x.o* | grep -E "\.o[0-9]+$" | tail -n 1)
stderrfile=$(ls -tr guess_x.e* | grep -E "\.e[0-9]+$" | tail -n 1)
lastjob=$(echo "${stdoutfile}" | grep -oE "[0-9]+")
thisdir=logs-${lastjob}
echo ${thisdir}/
mkdir -p ${thisdir}
cp -a guess_x.*${lastjob} ${thisdir}/
cp -a guess ${thisdir}/
cp -a latest* ${thisdir}/
cp -a submit.sh ${thisdir}/
cp -a *ins ${thisdir}/
cp -a ${gl} ${thisdir}/
cd ${thisdir}

gl_failcells=failcells.txt
gl_notruncells=notruncells.txt
gl_minusfailed=gridlist_minusfailed.txt
for f in ${gl_failcells} ${gl_notruncells}; do
   [[ -f $f ]] && rm $f
   touch $f
done
cp -a ../${gl} ${gl_minusfailed}

# Get logs
echo "   Getting logs..."
mkdir -p logs
set +e
for x in $(seq 0 $((nparts - 1))); do
   thisout="logs/run$((x+1)).out"
   thiserr="logs/run$((x+1)).err"
   if [[ ! -f "${thisout}" ]]; then
      grep "\[1,$x\]" ${stdoutfile} > "${thisout}"
      lastexit=$?
      if [[ $lastexit -ne 0 ]]; then
          echo "grep \"\[1,$x\]\" ${stdoutfile} > \"${thisout}\" : exited with code $lastexit"
          exit $lastexit
      fi
   fi
   if [[ ! -f "${thiserr}" ]]; then
      grep "\[1,$x\]" ${stderrfile} > "${thiserr}"
      if [[ $lastexit -ne 0 ]]; then
          echo "grep \"\[1,$x\]\" ${stderrfile} > \"${thiserr}\" : exited with code $lastexit"
          exit $lastexit
      fi
   fi
done
set -e

# Get list of failed cells
failranks=$(grep -i "invalid\|fail\|error" ${stdoutfile} | grep -v "Will fail if" | grep -oE "\[[0-9]+,[0-9]+\]" | sed -e "s/\[[0-9]\+,//" | sed "s/\]//")
Nfail=0
if [[ "${failranks}" != "" ]]; then
   echo "   Getting ${gl_failcells} and ${gl_minusfailed}..."
   for r in ${failranks}; do
       Nfail=$((Nfail + 1))
      thisfile=logs/run$(( r+1 )).out
      if [[ ! -e "${thisfile}" ]]; then
          echo "File ${thisfile} does not exist! Halting."
          exit 1
      fi
      tmp=$(grep "Commenc" logs/run$((r+1)).out | tail -n 1 | grep -oE " at .*$" | grep -oE "[-0-9\.]+,[-0-9\.]+" | head -n 1 | sed "s/(\|)//g" | sed "s/,/ /")
      if [[ "${tmp}" == "" ]]; then
          tmp=$(grep "Problems with" logs/run$((r+1)).out | tail -n 1 | grep -oE "[-0-9\.]+,[-0-9\.]+" | tail -n 1 | sed "s/,/ /")
      fi
      # It's possible that failures happened because of something that happened before any gridcells began
      if [[ "${tmp}" != "" ]]; then
        echo $tmp >> ${gl_failcells}
        sed -i "/${tmp}/d" ${gl_minusfailed}   
      fi
   done
fi

# Get not-run cells
Nnotrun=$(grep -L "Finished" logs/*.out | wc -l)
if [[ ${Nnotrun} -gt 0 ]]; then
   echo "   Getting ${gl_notruncells}..."
   for r in $(seq 1 ${nparts}); do
        thisfile="logs/run${r}.out"
        if [[ ! -e "${thisfile}" ]]; then
            echo "File ${thisfile} does not exist! Halting."
            exit 1
        fi
      set +e
      grep "Finished" "${thisfile}" >/dev/null
      if [[ $? -eq 0 ]]; then
         continue
      fi
      set -e
      g0=$(grep "Commenc" logs/run${r}.out | tail -n 1 | grep -oE " at .*$" | grep -oE "[-0-9\.]+,[-0-9\.]+" | head -n 1 | sed "s/(\|)//g" | sed "s/,/ /")
      grep -A 999999 "${g0/-/\\-}" ../run${r}/${gl} >> ${gl_notruncells}
   done
    if [[ $(cat "${gl_failcells}" | wc -l ) -gt 0 ]]; then
       echo "   Removing failed cells..."
       for r in ${failranks}; do
          tmp=$(grep "Commenc" logs/run$((r+1)).out | tail -n 1 | grep -oE " at .*$" | grep -oE "[-0-9\.]+,[-0-9\.]+" | head -n 1 | sed "s/(\|)//g" | sed "s/,/ /")
          if [[ "${tmp}" == "" ]]; then
              tmp=$(grep "Problems with" logs/run$((r+1)).out | tail -n 1 | grep -oE "[-0-9\.]+,[-0-9\.]+" | tail -n 1 | sed "s/,/ /")
          fi
          sed -i "/${tmp}/d" ${gl_notruncells}   
       done
    fi
fi

# Get text strings of bad cells, if any
if [[ $(wc -l ${gl_failcells} | cut -d" " -f1) -gt 0 ]]; then
    badcell="$(head -n 1 ${gl_failcells})"
    badcell=${badcell/-/\\-}
    badrun=$(grep "${badcell}" ../run*/$(basename "${gl}") | grep -oE "run[0-9]+")
    badcell=${badcell/\\/}
    eg_fail="(${Nfail} parts; e.g., ${badrun} ${badcell})"
fi
if [[ $(wc -l ${gl_notruncells} | cut -d" " -f1) -gt 0 ]]; then
    badcell="$(head -n 1 ${gl_notruncells})"
    badcell=${badcell/-/\\-}
    badrun=$(grep "${badcell}" ../run*/$(basename "${gl}") | grep -oE "run[0-9]+")
    badcell=${badcell/\\/}
    eg_notrun="(${Nnotrun} parts; e.g., ${badrun} ${badcell})"
fi

echo " "
echo "Results:"
wc -l ${gl} | sed "s/ /\t/"
echo "$(wc -l ${gl_failcells} | sed "s/ /\t/")" ${eg_fail}
echo "$(wc -l ${gl_notruncells} | sed "s/ /\t/")" ${eg_notrun}
wc -l ${gl_minusfailed} | sed "s/ /\t/"

exit 0








