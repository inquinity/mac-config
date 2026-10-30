#!/usr/bin/env zsh

# Git runs external aliases from the repository root. Restore the caller's
# directory so ordinary status output remains relative to where it was invoked.
if [[ -n ${GIT_PREFIX:-} ]]; then
    cd -- "$GIT_PREFIX" || exit 1
fi

git status "$@" || exit $?

# Preserve the output expected by callers requesting another status format.
if (( $# > 0 )); then
    exit 0
fi

worktrees=$(git worktree list --porcelain) || exit $?
current_path=$(git rev-parse --show-toplevel) || exit $?

worktree_count=0
while IFS= read -r line; do
    [[ $line == worktree\ * ]] && (( ++worktree_count ))
done <<< "$worktrees"

printf '\nWorktrees (%d):\n' "$worktree_count"

print_worktree() {
    local worktree_path=$1 head=$2 branch=$3
    local changes line index_status worktree_status marker=' '
    local staged=0 modified=0 untracked=0 conflicts=0
    local -a states

    [[ $worktree_path == "$current_path" ]] && marker='*'
    if [[ ! -d $worktree_path ]]; then
        worktree_status='missing'
    elif ! changes=$(git -C "$worktree_path" status --porcelain=v1 --untracked-files=normal 2>/dev/null); then
        worktree_status='unavailable'
    else
        while IFS= read -r line; do
            [[ -z $line ]] && continue
            index_status=${line[1]}
            worktree_status=${line[2]}
            if [[ $index_status == '?' && $worktree_status == '?' ]]; then
                (( ++untracked ))
            elif [[ $index_status == 'U' || $worktree_status == 'U' ||
                    ( $index_status == 'A' && $worktree_status == 'A' ) ||
                    ( $index_status == 'D' && $worktree_status == 'D' ) ]]; then
                (( ++conflicts ))
            else
                [[ $index_status != ' ' ]] && (( ++staged ))
                [[ $worktree_status != ' ' ]] && (( ++modified ))
            fi
        done <<< "$changes"
        (( staged )) && states+=("staged: $staged")
        (( modified )) && states+=("modified: $modified")
        (( untracked )) && states+=("untracked: $untracked")
        (( conflicts )) && states+=("conflicts: $conflicts")
        if (( ${#states} )); then
            worktree_status="${(j:, :)states}"
        else
            worktree_status='clean'
        fi
    fi

    printf '  %s %-32s %-8s %-24s %s\n' "$marker" "$branch" "${head[1,7]}" "$worktree_status" "$worktree_path"
}

worktree_path='' head='' branch=''
while IFS= read -r line; do
    case $line in
        'worktree '*) worktree_path=${line#worktree } ;;
        'HEAD '*) head=${line#HEAD } ;;
        'branch '*) branch=${line#branch refs/heads/} ;;
        'detached') branch='(detached)' ;;
        'bare') branch='(bare)' ;;
        'prunable '*) branch='(prunable)' ;;
        '')
            if [[ -n $worktree_path ]]; then
                print_worktree "$worktree_path" "$head" "${branch:-(unknown)}"
                worktree_path='' head='' branch=''
            fi
            ;;
    esac
done <<< "$worktrees"
[[ -n $worktree_path ]] && print_worktree "$worktree_path" "$head" "${branch:-(unknown)}"
