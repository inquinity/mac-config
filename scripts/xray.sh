#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.1.2
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/xray.sh

# Requirements:
# 1. jf cli installed

# Validate parameters
# TBD

# Set variables and save context
image_name="${1}"
datestr="$(date +%Y-%m-%d)"
basestr=$(echo "$(basename ${image_name})" | sed -r "s/:/--/g" )
scan_results="${datestr}_${basestr}_xray.txt"

#echo image_name: ${image_name}
#echo datestr: ${datestr}
#echo basestr: ${basestr}
#echo scan_results: ${scan_results}

if [ -f "${scan_results}" ] ; then
   rm "${scan_results}"
fi

jf docker scan ${image_name} > "${scan_results}"

# Display the results to the console
cat "${scan_results}"
