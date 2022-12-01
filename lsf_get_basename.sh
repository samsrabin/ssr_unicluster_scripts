#!/bin/bash

# Find the first directory above (or including) this one that is four_under-score_separated_words 
thisbasename=$(echo $PWD | { grep -oE "/[a-zA-Z0-9\-\.]+_[a-zA-Z0-9\-\.]+_[a-zA-Z0-9\-\.]+_[a-zA-Z0-9\-\.]+/" || true; } | tail -n 1 | sed "s@/@@g")

if [[ "${thisbasename}" == "" ]]; then
	>&2 echo "lsf_get_basename.sh: No matches found"
	>&2 echo PWD $PWD
	exit 1
fi

echo $thisbasename

exit 0
