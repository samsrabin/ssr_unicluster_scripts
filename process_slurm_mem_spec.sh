if [[ $mem_per_node -le 0 && $mem_per_cpu -le 0 ]]; then
    mem_spec="--mem-per-cpu ${mem_per_cpu_default}"
    echo "Neither --mem-per-cpu nor --mem-per-node specified; using '${mem_spec}'"
elif [[ $mem_per_node -gt 0 && $mem_per_cpu -gt 0 ]]; then
    mem_spec="--mem-per-cpu ${mem_per_cpu}"
    echo "Both --mem-per-cpu nor --mem-per-node specified; using '${mem_spec}'"
elif [[ $mem_per_node -gt 0 ]]; then
    mem_spec="--mem $mem_per_node"
elif [[ $mem_per_cpu -gt 0 ]]; then
    mem_spec="--mem-per-cpu $mem_per_cpu"
else
    echo "Error: Unhandled memory spec situation: --mem-per-node $mem_per_node --mem-per-cpu $mem_per_cpu"
    exit 1
fi

if [[ "${mem_spec}" == "--mem-per-cpu " || "${mem_spec}" == "--mem-per-node " ]]; then
    echo "Error: Invalid memory specification: ${mem_spec}"
    exit 1
fi
