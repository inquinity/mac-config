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

# Git always lists the main worktree first. It anchors the relative paths below
# and is excluded from both the listing and the count, which report only the
# linked worktrees.
main_path=''
worktree_count=0
while IFS= read -r line; do
    [[ $line == worktree\ * ]] || continue
    if [[ -z $main_path ]]; then
        main_path=${line#worktree }
    else
        (( ++worktree_count ))
    fi
done <<< "$worktrees"

if (( worktree_count == 0 )); then
    printf '\nWorktrees:\n  none\n'
    exit 0
fi

printf '\nWorktrees (%d):\n%s\n' "$worktree_count" "$main_path"

# Render an absolute path relative to the main worktree root, walking up with
# '..' segments for worktrees that live outside it.
relative_to_main() {
    local target=$1 base=$2
    local -a target_parts base_parts relative_parts
    local common=0 index

    [[ $target == "$base" ]] && { printf '.'; return 0; }

    target_parts=(${(s:/:)target})
    base_parts=(${(s:/:)base})

    # Compare whole path components so a sibling such as 'mac-backup-other' is
    # never mistaken for a child of 'mac-backup'.
    while (( common < ${#target_parts} && common < ${#base_parts} )) &&
          [[ ${target_parts[common+1]} == ${base_parts[common+1]} ]]; do
        (( ++common ))
    done

    for (( index = common + 1; index <= ${#base_parts}; index++ )); do
        relative_parts+=('..')
    done
    relative_parts+=(${target_parts[common+1,-1]})

    printf '%s' "${(j:/:)relative_parts}"
}

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

    printf '  %s %-32s %-8s %-24s %s\n' "$marker" "$branch" "${head[1,7]}" "$worktree_status" \
        "$(relative_to_main "$worktree_path" "$main_path")"
}

# Emit a parsed record unless it describes the main worktree, which the header
# above already reports.
flush_worktree() {
    local worktree_path=$1 head=$2 branch=$3

    [[ -z $worktree_path || $worktree_path == "$main_path" ]] && return 0
    print_worktree "$worktree_path" "$head" "${branch:-(unknown)}"
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
            flush_worktree "$worktree_path" "$head" "$branch"
            worktree_path='' head='' branch=''
            ;;
    esac
done <<< "$worktrees"
flush_worktree "$worktree_path" "$head" "$branch"
