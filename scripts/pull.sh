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

# Define the contexts and namespaces for different environments
context_np="ctc-nonprd-usr001-ctc-nonprd-usr001-default-cli-user"
namespace_dev="orx-dso-tools-np"
context_prod="elr-prd-usr101-elr-prd-usr101-default-cli-user"
namespace_prod="orx-dso-tools-p"

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

	    eval "$( kubectl -n $namespace describe deployment nextjs-demo-ui  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe deployment azure-nsg-logs-data-api-dev  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe deployment azure-nsg-logs-splunk-search-api-dev  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe deployment cnsla-ui-dev  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe cronjob cnsla-database-backup-dev  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
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

	    eval "$( kubectl -n $namespace describe deployment azure-nsg-logs-data-api-test  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe deployment azure-nsg-logs-splunk-search-api-test  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe deployment cnsla-ui-test  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe cronjob cnsla-database-backup-test  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
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

        eval "$( kubectl -n $namespace describe deployment azure-nsg-logs-data-api-prod  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe deployment azure-nsg-logs-splunk-search-api-prod  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe deployment cnsla-ui-prod  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl -n $namespace describe cronjob cnsla-database-backup-prod  | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"

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
