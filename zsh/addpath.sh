# addpath [--prepend|--append|--move] DIRECTORY
#
#   --prepend  (default) Add to the front of $PATH; no-op if already present.
#   --append             Add to the end of $PATH; no-op if already present.
#   --move               Add to the front, relocating it if already present.
#
# --move exists because macOS /etc/zprofile runs /usr/libexec/path_helper, which
# rebuilds $PATH with /etc/paths and /etc/paths.d first -- demoting anything
# .zshenv prepended to below /usr/bin. See the precedence block in .zprofile.
#
# Silent by design: sourced from .zshenv for every shell, including
# non-interactive ones, where stray output would corrupt command substitution.
addpath() {
    local mode="prepend"
    local input_path=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --prepend|-p) mode="prepend" ;;
            --append|-a)  mode="append" ;;
            --move|-m)    mode="move" ;;
            --help|-h)
                printf "usage: addpath [--prepend|--append|--move] DIRECTORY\n"
                return 0
                ;;
            --) shift; input_path="$1" ;;
            -*)
                printf "addpath: unknown option: %s\n" "$1" >&2
                return 2
                ;;
            *) input_path="$1" ;;
        esac
        shift
    done

    if [[ -z "$input_path" ]]; then
        printf "usage: addpath [--prepend|--append|--move] DIRECTORY\n" >&2
        return 2
    fi

    local dir_path
    case "$input_path" in
        "~")   dir_path="$HOME" ;;
        "~/"*) dir_path="$HOME/${input_path#~/}" ;;
        *)     dir_path="$input_path" ;;
    esac

    # Normalize a trailing slash so /foo and /foo/ are treated as one entry.
    [[ "$dir_path" != "/" ]] && dir_path="${dir_path%/}"

    [[ -d "$dir_path" ]] || return 0

    if [[ "$mode" == "move" ]]; then
        # Drop every existing occurrence, then prepend. $path and $PATH are tied in zsh.
        local -a kept
        local entry
        for entry in "${path[@]}"; do
            [[ "$entry" == "$dir_path" ]] || kept+=("$entry")
        done
        path=("$dir_path" "${kept[@]}")
        return 0
    fi

    # prepend / append are no-ops when the directory is already present
    [[ ":$PATH:" == *":$dir_path:"* ]] && return 0

    if [[ "$mode" == "append" ]]; then
        export PATH="$PATH:$dir_path"
    else
        export PATH="$dir_path:$PATH"
    fi
}
