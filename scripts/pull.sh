#!/bin/zsh

if [ $# -eq 0 ]
  then
    echo "No arguments supplied. Valid arguments: dev, test, prod (or all)."
fi

while test $# -gt 0
do
    case $1 in
        dev|all)
	    echo dev
	    kubectl config use-context anthos-orx-dso-tools-np
	    eval "$( kubectl describe deployment azure-nsg-logs-data-api-dev 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl describe deployment azure-nsg-logs-splunk-search-api-dev 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl describe deployment azure-nsg-logs-ui-dev 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    valid_arg_found=1
            ;|
       test|all)
	    echo test
	    kubectl config use-context anthos-orx-dso-tools-np
	    eval "$( kubectl describe deployment azure-nsg-logs-data-api-test 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl describe deployment azure-nsg-logs-splunk-search-api-test 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl describe deployment azure-nsg-logs-ui-test 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    valid_arg_found=1
            ;|
	prod|all)
	    echo prod
	    kubectl config use-context anthos-orx-dso-tools-p
	    eval "$( kubectl describe deployment azure-nsg-logs-data-api-prod 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl describe deployment azure-nsg-logs-splunk-search-api-prod 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    eval "$( kubectl describe deployment azure-nsg-logs-ui-prod 2>/dev/null | grep Image | sed 's/[[:blank:]]*Image:[[:blank:]]*/docker image pull /g' )"
	    kubectl config use-context anthos-orx-dso-tools-np
	    valid_arg_found=1
	    ;;
    esac
    shift
done

if [ -z valid_arg_found ]
    then echo "Argument \"$1\" is not supported; try dev, test, or prod (or all)."
fi

exit 0
