#!/bin/bash
#SBATCH -p dev_single
#SBATCH --time=30:00
#SBATCH -n 1

# Whatever arguments are given to this script will be passed to guess.

valgrind --track-origins=yes --error-limit=no --log-file=valgrind.log ../guess -input $@

exit 0
