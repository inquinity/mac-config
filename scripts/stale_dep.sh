#! /bin/zsh
echo "As a result of the redacted columns, this is a no-op!"
exit

combined_file=stale.csv
echo stale dependecy file: $1
echo Stale Packages file: $2
#
# csvjoin -y 0 --no-inference <(csvsort -c 1 $1) <(csvsort -c 1 $2) | csvcut -c 1,2,3,4,6,10,11,17,18,22,23 | csvsort -c 5,1 > $combined_file
#

#csvsort --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks --columns "Dependency Name" AIDE_0074431_staleDependencies_03_25_2024.csv > a.csv
#echo done1
#csvsort --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks --columns "Name/Package" AIDE_0074431_StaleDependency_Secure_Code_Vulnerabilities.csv > b.csv
#echo done2
#csvjoin --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks --columns "Dependency Name","Name/Package" a.csv b.csv > joined.csv
#echo done3
#csvcut --delimiter , --quotechar \"  --columns "Dependency Name","Current Version",Release,"Latest Version",Recommendation,"Stale Package" joined.csv > cut.csv

csvjoin --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks --columns "Dependency Name","Name/Package" \
    <(csvsort --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks --columns "Dependency Name" $1) \
    <(csvsort --no-inference --snifflimit 0 --delimiter , --quotechar \" --blanks --columns "Name/Package" $2) \
| csvcut --delimiter , --quotechar \"  --columns "Dependency Name","Current Version",Release,"Latest Version",Recommendation,"Stale Package" > $combined_file

#csvjoin --no-inference --snifflimit 0 --delimiter , --quotechar \" \
#	<(csvsort --no-inference -c "Dependency Name" $1) <(csvsort --no-inference -c "Name/Package" $2) \
#    | csvcut --delimiter , --quotechar \" -c "Dependency Name","CurrentVersion",Release,"Latest Version",Recommendation,"Tool Identified","Github Location",Description,"Package Details",Remediation,"Unique ID" | csvsort -c Recommendation,"Dependency Name" > $combined_file


echo Results file: $combined_file

# csvcut -n $1
# staleDependencies
#  1: Dependency Name
#  2: Current Version
#  3: Release
#  4: Latest Version
#  5: - Identified
#  6: Recommendation

#csvcut -n $2
# StalePackages
#  7: - Name/Package
#  8: - Stale Package
#  9: - ID
# 10: Tool Identified
# 11: Github Location
# 12: - ID Date
# 13: - CVSS3 Score
# 14: - SLA Countdown
# 15: - Status
# 16: - Severity
# 17: Description
# 18: Package Details
# 19: - Stack Trace
# 20: - Date Bypassed
# 21: - Bypassed by User
# 22: Remediation
# 23: Unique ID

# sort staleDependencies csv file
#csvsort -c 1 $1

# sort StalePackagesDetected_Secure_Code_Vulnerabilities csv file
#csvsort -c 1 $2

# join on StalePackages."Name/Package" = staleDependencies."Dependency Name"
# csvjoin -y 0 --no-inference $1 $2

# remove staleDependencies.Identified
# remove StalePackages.Name/Package
# remove StalePackages.Stale Package
# remove StalePackages.ID
# remove StalePackages.ID Date
# remove StalePackages.CVSS3 Score
# remove StalePackages.SLA Countdown
# remove StalePackages.Status
# remove StalePackages.Severity
# remove StalePackages.Stack Trace
# remove StalePackages.Date Bypassed
# remove StalePackages.Bypassed by
#csvcut -c 1,2,3,4,6,10,11,12,18,19,23,24

# sort by Recommendation, Dependency Name
#csvsort -c 6,1

