#!/bin/zsh

# Source common kubectl functions
source ~/team/scripts/kubectl_common.shlib

# Check arguments
check_arguments $*

# Date threshold for warning
date_threshold_warning=25

# Define the contexts and namespaces for different environments
context_np="ctc-nonprd-usr001-ctc-nonprd-usr001-default-cli-user"
namespace_dev="orx-dso-tools-np"
context_prod="elr-prd-usr101-elr-prd-usr101-default-cli-user"
namespace_prod="orx-dso-tools-p"

# JQ expression for golden image release date
jq_expr='.[0].Config.Labels."golden.container.image.build.release"'

# Define deployments and cronjobs for each environment
dev_deployments=("nextjs-demo-ui" "azure-nsg-logs-data-api-dev" "azure-nsg-logs-splunk-search-api-dev" "cnsla-ui-dev")
dev_cronjobs=("cnsla-database-backup-dev")

test_deployments=("azure-nsg-logs-data-api-test" "azure-nsg-logs-splunk-search-api-test" "cnsla-ui-test")
test_cronjobs=("cnsla-database-backup-test")

prod_deployments=("azure-nsg-logs-data-api-prod" "azure-nsg-logs-splunk-search-api-prod" "cnsla-ui-prod")
prod_cronjobs=("cnsla-database-backup-prod")

# Main script logic
valid_arg_found=""
last_arg=""
while test $# -gt 0
do
    last_arg=$1
    case $1 in
        d|dev|all)
            context=$context_np
            namespace=$namespace_dev
            print_environment_header "Development" $context $namespace
            switch_context $context

            # Process deployments
            for deployment in "${dev_deployments[@]}"; do
                query_and_print_image $namespace "deployment" $deployment "$jq_expr"
            done
            
            # Process cronjobs
            for cronjob in "${dev_cronjobs[@]}"; do
                query_and_print_image $namespace "cronjob" $cronjob "$jq_expr"
            done
            
            valid_arg_found=1
            ;|
        t|test|all)
            context=$context_np
            namespace=$namespace_dev
            print_environment_header "Test" $context $namespace
            switch_context $context

            # Process deployments
            for deployment in "${test_deployments[@]}"; do
                query_and_print_image $namespace "deployment" $deployment "$jq_expr"
            done
            
            # Process cronjobs
            for cronjob in "${test_cronjobs[@]}"; do
                query_and_print_image $namespace "cronjob" $cronjob "$jq_expr"
            done
            
            valid_arg_found=1
            ;|
        p|prod|all)
            context=$context_prod
            namespace=$namespace_prod
            print_environment_header "Prod" $context $namespace
            switch_context $context

            # Process deployments
            for deployment in "${prod_deployments[@]}"; do
                query_and_print_image $namespace "deployment" $deployment "$jq_expr"
            done
            
            # Process cronjobs
            for cronjob in "${prod_cronjobs[@]}"; do
                query_and_print_image $namespace "cronjob" $cronjob "$jq_expr"
            done

            # Reset context to non-prod if needed (safety)
            kubectl config use-context $context_np
            valid_arg_found=1
            ;;
    esac
    shift
done

# Check if a valid argument was found
check_valid_args "$valid_arg_found" "$last_arg"

exit 0
