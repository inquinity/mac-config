#!/bin/zsh

# Define color codes for terminal output
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_MAGENTA="\e[35m"
COLOR_BRIGHTYELLOW="\e[93m"
COLOR_RESET="\e[0m"

if [ $# -eq 0 ]
  then
    printf "\n${COLOR_RED}No arguments supplied. Valid arguments: dev, test, prod (or all).${COLOR_RESET}\n"
fi

# Date threshold for warning
date_threshold_warning=25

# Define the contexts and namespaces for different environments
context_np="ctc-nonprd-usr001-ctc-nonprd-usr001-default-cli-user"
namespace_dev="orx-dso-tools-np"
context_prod="elr-prd-usr101-elr-prd-usr101-default-cli-user"
namespace_prod="orx-dso-tools-p"

jq_expr='.[0].Config.Labels."golden.container.image.build.release"'

# Helper function to print release date with color if over 5 days old
print_release_date() {
    local image="$1"
    local jq_expr="$2"
    local msg_release="    Golden Image Release Date: %s\n"
    local msg_release_days="    Golden Image Release Date: %s\n    Image is %s days old\n"
    local msg_release_days_red="    ${COLOR_RED}Golden Image Release Date: %s\n    Image is %s days old${COLOR_RESET}\n"
    local release_date
    release_date=$(docker inspect "$image" | jq -r "$jq_expr")
    if [[ "$release_date" == "null" || -z "$release_date" ]]; then
        printf "$msg_release" "$release_date"
        return
    fi
    # Expecting release_date in format YYYY.MM.DD
    local release_epoch=""
    if [[ "$release_date" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
        # Convert to YYYY-MM-DD for date command
        local release_date_fmt="${release_date//./-}"
        # BSD date (macOS): -j -f "%Y-%m-%d"
        release_epoch=$(date -j -f "%Y-%m-%d" "$release_date_fmt" +"%s" 2>/dev/null)
        # GNU date fallback (Linux): date -d
        if [[ -z "$release_epoch" ]]; then
            release_epoch=$(date -d "$release_date_fmt" +"%s" 2>/dev/null)
        fi
    fi
    now_epoch=$(date +%s)
    local diff_days=""
    if [[ -n "$release_epoch" ]]; then
        diff_days=$(( (now_epoch - release_epoch) / 86400 ))
        if (( diff_days > ${date_threshold_warning} )); then
            printf "$msg_release_days_red" "$release_date" "$diff_days"
        else
            printf "$msg_release_days" "$release_date" "$diff_days"
        fi
    else
        printf "$msg_release" "$release_date"
    fi
}

# kubectl config use-context cect-dev-hcc-dev-namespace
while test $# -gt 0
do
    case $1 in
        d|dev|all)
        context=$context_np
        namespace=$namespace_dev
        printf "\n${COLOR_BRIGHTYELLOW}Getting information for Development${COLOR_RESET}\n"
        printf "${COLOR_BRIGHTYELLOW}Context: ${context}${COLOR_RESET}\n"
        printf "${COLOR_BRIGHTYELLOW}Namespace: ${namespace}${COLOR_RESET}\n"

        current_context=$(kubectl config current-context)
        if [ "$current_context" != "$context" ]; then
            kubectl config use-context $context
        fi

        image=$(kubectl -n $namespace describe deployment nextjs-demo-ui | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe deployment azure-nsg-logs-data-api-dev | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe deployment azure-nsg-logs-splunk-search-api-dev | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe deployment cnsla-ui-dev | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe cronjob cnsla-database-backup-dev | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        valid_arg_found=1
            ;|
       t|test|all)
        context=$context_np
        namespace=$namespace_dev
        printf "\n${COLOR_BRIGHTYELLOW}Getting information for Test${COLOR_RESET}\n"
        printf "${COLOR_BRIGHTYELLOW}Context: ${context}${COLOR_RESET}\n"
        printf "${COLOR_BRIGHTYELLOW}Namespace: ${namespace}${COLOR_RESET}\n"

        current_context=$(kubectl config current-context)
        if [ "$current_context" != "$context" ]; then
            kubectl config use-context $context
        fi

        image=$(kubectl -n $namespace describe deployment azure-nsg-logs-data-api-test | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe deployment azure-nsg-logs-splunk-search-api-test | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe deployment cnsla-ui-test | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe cronjob cnsla-database-backup-test | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        valid_arg_found=1
            ;|
	p|prod|all)
        context=$context_prod
        namespace=$namespace_prod
        printf "\n${COLOR_BRIGHTYELLOW}Getting information for Prod${COLOR_RESET}\n"
        printf "${COLOR_BRIGHTYELLOW}Context: ${context}${COLOR_RESET}\n"
        printf "${COLOR_BRIGHTYELLOW}Namespace: ${namespace}${COLOR_RESET}\n"

         current_context=$(kubectl config current-context)
        if [ "$current_context" != "$context" ]; then
            kubectl config use-context $context
        fi

        image=$(kubectl -n $namespace describe deployment azure-nsg-logs-data-api-prod | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe deployment azure-nsg-logs-splunk-search-api-prod | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe deployment cnsla-ui-prod | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"
        image=$(kubectl -n $namespace describe cronjob cnsla-database-backup-prod | grep Image | sed 's!^[[:blank:]]*Image:[[:blank:]]*!!g')
        printf "%s\n" "$image"; print_release_date "$image" "$jq_expr"

        # Reset context to anthos-orx-dso-tools-np if needed (safety)
	    kubectl config use-context $context_np
	    valid_arg_found=1
	    ;;
    esac
    shift
done

# Check if a valid argument was found
if [ -z valid_arg_found ]; then
    printf "\n${COLOR_RED}Argument \"$1\" is not supported; try dev, test, or prod (or all).${COLOR_RESET}\n"
fi

exit 0
