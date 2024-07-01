#!/bin/zsh
#echo $(basename -- "$1")
#echo "${1##*.}"
#
# Set up filenames
namepart="${1%.*}"
filename=${1}
filename_cve="${namepart}_cve.csv"
filename_orig="${namepart}_orig.csv"

# show columns
# csvcut -n data.csv
 #  1: Name
 #  2: ID
 #  3: CSP
 #  4: Environment
 #  5: Tool Identified
 #  6: ID Date
 #  7: CVSS3 Score
 #  8: SLA Countdown
 #  9: Status
 # 10: Severity
 # 11: Description
 # 12: Resource Type
 # 13: AMI Name
 # 14: Instance Name
 # 15: Instance ID
 # 16: Instance Resource Tags
 # 17: AKS Image Name
 # 18: Package Details
 # 19: Fix Version
 # 20: OS Details
 # 21: Remediation
 # 22: Is Managed
 # 23: Unique ID
#
#echo "${1##*/}"
# Show filenames
#echo Parameter: ${1}
#echo Namepart: ${namepart}
#echo Filename: ${filename}
#echo Original File: ${filename_orig}
#echo CVE File: ${filename_cve}

# Rename original file
mv ${1} ${filename_orig}

# Version 1: use sed and grep
#sed -n '1,1p' ${filename_orig} > ${filename_cve}
#grep -F -f ~/security/cve/cve_feb2024.txt -f ~/security/cve/cve_june2023.txt ${filename_orig} >> ${filename_cve}
#grep -F -v -f ~/security/cve/cve_feb2024.txt -f ~/security/cve/cve_june2023.txt ${filename_orig} > ${filename}

# Version 2: use csvkit; show only Not IsManaged
#csvgrep -f <(cat ~/security/cve/cve_feb2024.txt ~/security/cve/cve_june2023.txt) -c ID ${filename_orig} | csvgrep -c Severity -m FALSE | csvsort -c ID > ${filename_cve}
#csvgrep -f <(cat ~/security/cve/cve_feb2024.txt ~/security/cve/cve_june2023.txt) -c ID --invert-match ${filename_orig} | csvgrep -c Severity -m FALSE | csvsort -c ID > ${filename}

# Version 2: use csvkit; show all rows
csvgrep -f <(cat ~/security/cve/cve_feb2024.txt ~/security/cve/cve_june2023.txt) -c ID ${filename_orig} | csvsort -c Severity, ID > ${filename_cve}
csvgrep -f <(cat ~/security/cve/cve_feb2024.txt ~/security/cve/cve_june2023.txt) -c ID --invert-match ${filename_orig} | csvsort -c Severity, ID > ${filename}
