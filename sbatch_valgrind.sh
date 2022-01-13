#!/bin/bash
#SBATCH -p dev_single
#SBATCH --time=30:00
#SBATCH -n 1

# USAGE (from parallel sub-run directory):
#   sbatch ~/scripts/sbatch_valgrind.sh -input cfx main.ins

$HOME/scripts_peter/module_gnu.sh

#valgrind -s --track-origins=yes --error-limit=no --leak-check=full --log-file=valgrind.log ../guess $@
valgrind -s --track-origins=yes --error-limit=no --log-file=valgrind.log ../guess $@

exit 0
