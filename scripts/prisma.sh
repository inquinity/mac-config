#!/bin/bash

# This script is authored by Robert Altman, OptumRx
# robert.altman@optum.com
# Version 1.1.2
# https://github.com/optum-rx-tech-ops/devsecops-team/blob/main/Docker/Scripts/prisma.sh

# Requirements:
# 1. twistcli installed
# 2. user must have Prisma Compute permissions in secure
#
# Prisma Compute (aka Twistlock) info: https://enterprise-cloud-security.optum.com/cloud-security/prisma-compute

# Validate parameters
# TBD

# Set variables and save context
image_name="${1}"
username=${USER}
datestr="$(date +%Y-%m-%d)"
basestr=$(echo "$(basename ${image_name})" | sed -r "s/:/--/g" )
scan_results="${datestr}_${basestr}_prisma.txt"

#echo image_name: ${image_name}
#echo datestr: ${datestr}
#echo basestr: ${basestr}
#echo username: ${username}
#echo scan_results: ${scan_results}

if [ -f "${scan_results}" ] ; then
   rm "${scan_results}"
fi

# the --output-file FILE.txt option will output a JSON detail, but is hard to read
# twistcli images scan --address https://containersecurity.optum.com --user ms\\${username} --details --publish --output-file "${scan_results}" ${image_name}
# instead, we capture the console output to file

# Show a password prompt and then pipe all output to a file
printf "%s" "Enter Password for ms\\${username}:"
twistcli images scan --address https://containersecurity.optum.com --user ms\\${username} --details ${image_name} | sed '1,3d' > "${scan_results}"

printf "\n"
printf "Results saved to ${scan_results}\n"

# Display the results to the console
cat "${scan_results}"

# To automatically open the results in Chrome, uncomment the following lines...
# results_url=$(grep Link "${scan_results}" | sed -r "s/Link.*http/http/g")
# open -n -a "Google Chrome" --args '--new-window' "${results_url}"
