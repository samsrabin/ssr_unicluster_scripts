#!/bin/bash

for ws in $(ws_list | grep -E "^id:" | cut -d " " -f 2); do
    ws_extend ${ws} 999
done

exit 0
