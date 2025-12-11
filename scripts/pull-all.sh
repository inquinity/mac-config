#!/bin/zsh

# pull-all.sh
# Version: 1.1
# Author: raltman2
# Description: Intelligently updates all git repositories by fetching from all remotes
#              and fast-forwarding local branches that track origin/*. For the current
#              branch, uses git merge --ff-only. For other branches, directly updates
#              refs. Skips branches that don't track origin or are already up-to-date.

# Disable xtrace to prevent variable assignment output
setopt noxtrace

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_MAGENTA="\e[35m"       # Available for general use
COLOR_CYAN="\e[36m"          # Available for general use
COLOR_BLUE="\e[34m"          # Available for general use; does not show on screen well
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# Update a single repository
update_repository() {
    local repo_path="$1"
    
    pushd "$repo_path" > /dev/null || return 1
    
    print_colored "${COLOR_GREEN}" "$(pwd)"
    
    # Check if origin remote exists
    if ! git remote | grep -q "^origin$"; then
        print_colored "${COLOR_RED}" "  ERROR: origin remote not found"
        popd > /dev/null
        return 1
    fi
    
    # Fetch all remotes
    git fetch --all
    
    # Get current branch (empty if detached HEAD)
    local current_branch
    current_branch="$(git symbolic-ref --short HEAD 2>/dev/null)"
    print_colored "${COLOR_CYAN}" "  Current branch: ${current_branch:-<detached HEAD>}"
    
    # Enumerate local branches that track origin/* using process substitution
    while read -r local_branch upstream_branch; do
        # Skip if no upstream or upstream is not origin/*
        [[ -z "$upstream_branch" ]] && continue
        [[ "$upstream_branch" != origin/* ]] && continue
        
        # Get the remote branch name
        local remote_branch="${upstream_branch#origin/}"
        
        # Check if remote branch exists
        if ! git rev-parse --verify "origin/$remote_branch" >/dev/null 2>&1; then
            continue
        fi
        
        # Get commit hashes
        typeset local_commit="$(git rev-parse "$local_branch" 2>/dev/null)" 
        typeset remote_commit="$(git rev-parse "origin/$remote_branch" 2>/dev/null)"
        
        # Skip if already up to date
        if [[ "$local_commit" == "$remote_commit" ]]; then
            print_colored "${COLOR_CYAN}" "  ✓ Up-to-date: $local_branch"
            continue
        fi
        
        # Show which branch we're updating
        print_colored "${COLOR_MAGENTA}" "  Branch needs update: $local_branch -> $upstream_branch"
        
        # Differentiate between current branch and others
        if [[ "$local_branch" == "$current_branch" ]]; then
            # Case 3: Current branch - use fast-forward merge
            print_colored "${COLOR_CYAN}" "  Updating current branch: $local_branch"
            if git merge --ff-only "origin/$remote_branch"; then
                print_colored "${COLOR_GREEN}" "  ✓ Updated current branch: $local_branch"
            else
                print_colored "${COLOR_YELLOW}" "  ⚠ Cannot fast-forward current branch: $local_branch (diverged)"
            fi
        else
            # Case 2: Non-current branch - update ref directly
            if git update-ref "refs/heads/$local_branch" "origin/$remote_branch" "$local_commit" 2>/dev/null; then
                print_colored "${COLOR_GREEN}" "  ✓ Updated branch: $local_branch"
            else
                print_colored "${COLOR_YELLOW}" "  ⚠ Failed to update branch: $local_branch"
            fi
        fi
    done < <(git for-each-ref --format='%(refname:short) %(upstream:short)' refs/heads/)
    
    # Return to previous directory
    popd > /dev/null
    return 0
}

# Check for optional subdirectory parameter
if [ $# -eq 1 ]; then
    subdirectory="$1"
    # Check for help request
    if [ "$subdirectory" = "help" ] || [ "$subdirectory" = "-h" ] || [ "$subdirectory" = "--help" ]; then
        print_colored "${COLOR_YELLOW}" "Usage: $0 [subdirectory]"
        print_colored "${COLOR_YELLOW}" "Examples:"
        print_colored "${COLOR_YELLOW}" "  $0          # Update all git repositories"
        print_colored "${COLOR_YELLOW}" "  $0 team     # Update only repositories in ./team directory"
        exit 0
    fi
    if [ ! -d "$subdirectory" ]; then
        print_colored "${COLOR_RED}" "Error: Subdirectory '$subdirectory' not found."
        exit 1
    fi
    print_colored "${COLOR_BRIGHTYELLOW}" "Starting pull-all script for subdirectory: $subdirectory"
    search_path="./$subdirectory"
elif [ $# -eq 0 ]; then
    print_colored "${COLOR_BRIGHTYELLOW}" "Starting pull-all script for all directories"
    search_path="."
else
    print_colored "${COLOR_RED}" "Usage: $0 [subdirectory]"
    print_colored "${COLOR_YELLOW}" "Examples:"
    print_colored "${COLOR_YELLOW}" "  $0          # Update all git repositories"
    print_colored "${COLOR_YELLOW}" "  $0 team     # Update only repositories in ./team directory"
    exit 1
fi

# Find all git repositories, pruning when we find one (don't search inside repos)
find "$search_path" -name ".git" -type d -prune -print0 | while IFS= read -r -d '' git_dir; do
    repo_path="$(dirname "$git_dir")"
    update_repository "$repo_path"
done
