#!/bin/bash

# DO NOT set -e, because we don't want a failure here to prevent the rest of the postprocessing

# Set up script
echo "dir_in = '$PWD' ;" > postproc.m
cat $HOME/GGCMI/matlab-ggcmi3/out/isimip3_pp_parent.m >> postproc.m

# Run script
module load math/matlab/R2020a
matlab -batch "run('postproc.m')"

exit 0
