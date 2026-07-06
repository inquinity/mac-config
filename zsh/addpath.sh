addpath() {
    local input_path=$1
    local dir_path

    case "$input_path" in
        "~") dir_path="$HOME" ;;
        "~/"*) dir_path="$HOME/${input_path#~/}" ;;
        *) dir_path="$input_path" ;;
    esac

    if [ -d "$dir_path" ] && [[ ":$PATH:" != *":$dir_path:"* ]]; then
        export PATH="$dir_path:$PATH"
    fi
}
