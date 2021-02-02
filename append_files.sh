#!/bin/bash

echo $# $0 $1 $2 $3 $4 $5 $6 $7 $8
number_of_jobs=$1
shift
while [ $# -gt 0 ] 
do 
file=$1
echo ${file}
if [[ -e run1/$file ]]; then
  cp run1/$file ${file}

  i=""
  for ((i=2; i <= number_of_jobs; i++))
  do
    cat run$i/$file | awk 'NR!=1 || NF==0 || $1 == $1+0 { print $0 }' >> ${file}
  done
fi
shift

done


