#!/usr/bin/env bash
# move-claude-folder.sh - move a project folder and carry its Claude sessions along.
#
# Usage: move-claude-folder.sh [--apply] SOURCE DEST
#        move-claude-folder.sh --verify SOURCE DEST
#        move-claude-folder.sh --list-backups
#        move-claude-folder.sh [--apply] --clean-backups [DAYS]
#        move-claude-folder.sh [--apply] --remove-backup NAME
#
# Discovered and updated (SOURCE = old path, DEST = new path):
#   1. The folder itself (mv), unless it was already moved by hand
#   2. ~/.claude/projects/<encoded-path>/ transcripts and memory (moved, not edited),
#      including nested projects under SOURCE (verified through the cwd in transcripts)
#   3. Claude desktop app session metadata (local_*.json) - path rewritten
#   4. ~/.claude.json project entries - keys remapped and merged (existing DEST wins)
#   5. ~/.claude/history.jsonl - path rewritten
#   6. Git worktree links (git worktree repair) when DEST is a git repository
# Anything else under ~/.claude that mentions SOURCE is reported but not modified.
#
# Bash 3.2 compatible (macOS default). Dry-run unless --apply is given.
set -euo pipefail

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

CLAUDE_HOME="${HOME}/.claude"
PROJECTS_DIR="${CLAUDE_HOME}/projects"
CLAUDE_JSON="${HOME}/.claude.json"
HISTORY_FILE="${CLAUDE_HOME}/history.jsonl"
APP_SESSIONS_DIR="${HOME}/Library/Application Support/Claude/claude-code-sessions"
BACKUP_ROOT="${HOME}/claude-folder-move-backups"
DEFAULT_RETENTION_DAYS=14

APPLY=0
MODE="move"
SOURCE_PATH=""
DEST_PATH=""
MODE_ARGUMENT=""
BACKUP_DIR=""
WORK_DIR=""
BEFORE_FILE_COUNT=""

usage() {
    print_colored "$COLOR_YELLOW" "Usage:"
    print_colored "$COLOR_YELLOW" "  $(basename "$0") [--apply] SOURCE DEST      Move a folder and its Claude sessions"
    print_colored "$COLOR_YELLOW" "  $(basename "$0") --verify SOURCE DEST       Check a finished move (read-only)"
    print_colored "$COLOR_YELLOW" "  $(basename "$0") --list-backups             List backups with age and size"
    print_colored "$COLOR_YELLOW" "  $(basename "$0") [--apply] --clean-backups [DAYS]"
    print_colored "$COLOR_YELLOW" "                                              Delete backups older than DAYS (default ${DEFAULT_RETENTION_DAYS})"
    print_colored "$COLOR_YELLOW" "  $(basename "$0") [--apply] --remove-backup NAME"
    print_colored "$COLOR_YELLOW" "                                              Delete one backup by name"
    print_colored "$COLOR_YELLOW" "Options:"
    print_colored "$COLOR_YELLOW" "  --apply     Make the changes (default is a dry run)"
    print_colored "$COLOR_YELLOW" "  -h, --help  Show this help"
    print_colored "$COLOR_YELLOW" "Quit the Claude desktop app and claude CLI sessions before --apply."
    print_colored "$COLOR_YELLOW" "To roll back a move, run it again with SOURCE and DEST swapped."
}

die() {
    print_colored "$COLOR_RED" "Error: $*" >&2
    exit 1
}

cleanup_work_dir() {
    [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
    return 0
}

# Run a command, or only print it in dry-run mode.
run() {
    if [[ $APPLY -eq 1 ]]; then
        "$@"
    else
        printf '  [dry-run]'
        printf ' %q' "$@"
        printf '\n'
    fi
}

# Claude Code names a project directory by replacing every non-alphanumeric
# character of the path with "-".
encode_path() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'
}

# Escape a string for use in a sed BRE pattern with "|" as the delimiter.
escape_sed_pattern() {
    printf '%s' "$1" | sed 's/[][\.*^$|/]/\\&/g'
}

# Escape a string for use in a sed replacement with "|" as the delimiter.
escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\&|]/\\&/g'
}

# Map a path under SOURCE_PATH to the same relative place under DEST_PATH.
map_path() {
    local original_path=$1
    printf '%s%s' "$DEST_PATH" "${original_path#"$SOURCE_PATH"}"
}

normalize_path() {
    local raw_path=$1
    [[ "$raw_path" == /* ]] || die "Path must be absolute: $raw_path"
    while [[ "$raw_path" != "/" && "$raw_path" == */ ]]; do
        raw_path=${raw_path%/}
    done
    printf '%s' "$raw_path"
}

# --------------------------------------------------------------------------
# Discovery
# --------------------------------------------------------------------------

# Read the working directory recorded in a project directory's first transcript.
project_dir_cwd() {
    local project_dir=$1 transcript_file
    for transcript_file in "$project_dir"/*.jsonl; do
        [[ -f "$transcript_file" ]] || continue
        grep -m1 -o '"cwd":"[^"]*"' "$transcript_file" 2>/dev/null \
            | head -n1 | sed 's/^"cwd":"//; s/"$//' || true
        return 0
    done
}

# Build (once) a table "encoded SOURCE-relative path<TAB>DEST-relative path" for the
# real directories under the project. Transcripts keep their original cwd after a
# move, so the cwd check alone cannot recognise nested projects (such as
# .claude/worktrees/<name>) on a second move or a rollback; matching a real
# directory by its encoded name can.
build_nested_dir_table() {
    [[ -f "$WORK_DIR/nested-table" ]] && return 0
    local search_root=$SOURCE_PATH nested_dir relative_path
    [[ -d "$search_root" ]] || search_root=$DEST_PATH
    : > "$WORK_DIR/nested-table"
    [[ -d "$search_root" ]] || return 0
    while IFS= read -r nested_dir; do
        relative_path=${nested_dir#"$search_root"}
        printf '%s\t%s\n' "$(encode_path "$SOURCE_PATH$relative_path")" "$DEST_PATH$relative_path"
    done < <(find "$search_root" -mindepth 1 -maxdepth 5 \
        \( -name .git -o -name node_modules -o -name DerivedData -o -name .build -o -name build \) -prune \
        -o -type d -print 2>/dev/null) >> "$WORK_DIR/nested-table"
}

# Print "old_dir<TAB>new_dir" for every project dir at or under SOURCE_PATH.
discover_project_dirs() {
    local source_encoded project_dir project_name project_cwd mapped_path
    source_encoded=$(encode_path "$SOURCE_PATH")
    [[ -d "$PROJECTS_DIR" ]] || return 0
    for project_dir in "$PROJECTS_DIR"/*/; do
        project_dir=${project_dir%/}
        project_name=$(basename "$project_dir")
        if [[ "$project_name" == "$source_encoded" ]]; then
            printf '%s\t%s\n' "$project_dir" "$PROJECTS_DIR/$(encode_path "$DEST_PATH")"
        elif [[ "$project_name" == "$source_encoded"-* ]]; then
            # The encoding is lossy (a sibling like "<name>-2" also matches), so
            # accept the dir only if a transcript's cwd, or a real directory under
            # the project, proves it belongs here.
            project_cwd=$(project_dir_cwd "$project_dir")
            mapped_path=""
            if [[ "$project_cwd" == "$SOURCE_PATH"/* ]]; then
                mapped_path=$(map_path "$project_cwd")
            else
                build_nested_dir_table
                mapped_path=$(awk -F'\t' -v name="$project_name" '$1 == name { print $2; exit }' \
                    "$WORK_DIR/nested-table")
            fi
            if [[ -n "$mapped_path" ]]; then
                printf '%s\t%s\n' "$project_dir" "$PROJECTS_DIR/$(encode_path "$mapped_path")"
            fi
        fi
    done
}

# Files that mention SOURCE_PATH as a whole path (followed by a quote or slash).
files_with_reference() {
    local search_root=$1 include_pattern=$2 pattern
    [[ -e "$search_root" ]] || return 0
    pattern="$(escape_sed_pattern "$SOURCE_PATH")[\"/]"
    grep -rl --include="$include_pattern" -- "$pattern" "$search_root" 2>/dev/null || true
}

# Same test as files_with_reference, for a single file.
file_has_reference() {
    local target_file=$1 pattern
    [[ -f "$target_file" ]] || return 1
    pattern="$(escape_sed_pattern "$SOURCE_PATH")[\"/]"
    grep -q -- "$pattern" "$target_file" 2>/dev/null
}

count_files_in() {
    { find "$1" -type f 2>/dev/null || true; } | wc -l | tr -d ' '
}

# --------------------------------------------------------------------------
# Actions
# --------------------------------------------------------------------------

check_claude_not_running() {
    # CLAUDE_MOVE_SKIP_RUNNING_CHECK=1 exists only for testing against a fake HOME.
    [[ "${CLAUDE_MOVE_SKIP_RUNNING_CHECK:-0}" == "1" ]] && return 0
    if pgrep -x "Claude" >/dev/null 2>&1 || pgrep -x "claude" >/dev/null 2>&1; then
        if [[ $APPLY -eq 1 ]]; then
            die "Claude is still running. Quit the desktop app and any claude CLI sessions, then retry."
        fi
        print_colored "$COLOR_RED" "Warning: Claude is running (fine for a dry run, not for --apply)."
    fi
}

backup_state() {
    print_colored "$COLOR_BRIGHTYELLOW" "Step 1: back up files that will be edited"
    BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$(basename "$SOURCE_PATH")"
    # Two moves within the same second must not share a backup directory.
    local backup_suffix=1 backup_base=$BACKUP_DIR
    while [[ -e "$BACKUP_DIR" ]]; do
        backup_suffix=$((backup_suffix + 1))
        BACKUP_DIR="${backup_base}-${backup_suffix}"
    done
    run mkdir -p "$BACKUP_DIR/files"

    local backup_index=0 original_file backup_name
    {
        [[ -f "$CLAUDE_JSON" ]] && printf '%s\n' "$CLAUDE_JSON"
        file_has_reference "$HISTORY_FILE" && printf '%s\n' "$HISTORY_FILE"
        files_with_reference "$APP_SESSIONS_DIR" 'local_*.json'
        true
    } > "$WORK_DIR/backup-list"

    while IFS= read -r original_file; do
        backup_index=$((backup_index + 1))
        backup_name="${backup_index}__$(basename "$original_file")"
        run cp -p "$original_file" "$BACKUP_DIR/files/$backup_name"
        if [[ $APPLY -eq 1 ]]; then
            printf '%s\t%s\n' "$original_file" "files/$backup_name" >> "$BACKUP_DIR/manifest.tsv"
        fi
    done < "$WORK_DIR/backup-list"

    if [[ $APPLY -eq 1 ]]; then
        printf 'source\t%s\ndest\t%s\ncreated\t%s\n' \
            "$SOURCE_PATH" "$DEST_PATH" "$(date '+%Y-%m-%d %H:%M:%S')" > "$BACKUP_DIR/info.tsv"
    fi
    print_colored "$COLOR_YELLOW" "  $backup_index file(s) -> $BACKUP_DIR"
}

move_folder() {
    print_colored "$COLOR_BRIGHTYELLOW" "Step 2: move the folder"
    if [[ -e "$SOURCE_PATH" && -e "$DEST_PATH" ]]; then
        die "Both $SOURCE_PATH and $DEST_PATH exist; refusing to guess."
    elif [[ -e "$SOURCE_PATH" ]]; then
        run mkdir -p "$(dirname "$DEST_PATH")"
        run mv "$SOURCE_PATH" "$DEST_PATH"
    elif [[ -e "$DEST_PATH" ]]; then
        print_colored "$COLOR_YELLOW" "  Already moved (SOURCE missing, DEST present); continuing with references"
    else
        die "Neither $SOURCE_PATH nor $DEST_PATH exists."
    fi
}

move_project_dirs() {
    print_colored "$COLOR_BRIGHTYELLOW" "Step 3: move transcripts and memory"
    discover_project_dirs > "$WORK_DIR/project-dirs"
    if [[ ! -s "$WORK_DIR/project-dirs" ]]; then
        print_colored "$COLOR_YELLOW" "  No project directories found for this path"
        return 0
    fi

    local old_dir new_dir entry entry_name
    while IFS=$'\t' read -r old_dir new_dir; do
        print_colored "$COLOR_YELLOW" "  $(basename "$old_dir") -> $(basename "$new_dir")"
        if [[ ! -e "$new_dir" ]]; then
            run mv "$old_dir" "$new_dir"
            continue
        fi
        # Destination project dir exists: merge without overwriting anything.
        for entry in "$old_dir"/*; do
            [[ -e "$entry" ]] || continue
            entry_name=$(basename "$entry")
            if [[ "$entry_name" == "memory" && -d "$new_dir/memory" ]]; then
                merge_directory "$entry" "$new_dir/memory"
            elif [[ -e "$new_dir/$entry_name" ]]; then
                print_colored "$COLOR_RED" "    Kept existing, skipped: $entry_name"
            else
                run mv "$entry" "$new_dir/$entry_name"
            fi
        done
        if [[ $APPLY -eq 1 ]]; then
            rmdir "$old_dir" 2>/dev/null \
                || print_colored "$COLOR_YELLOW" "    Old dir not empty, left in place: $old_dir"
        else
            printf '  [dry-run] rmdir %q (only if empty)\n' "$old_dir"
        fi
    done < "$WORK_DIR/project-dirs"
}

merge_directory() {
    local from_dir=$1 into_dir=$2 item
    for item in "$from_dir"/*; do
        [[ -e "$item" ]] || continue
        if [[ -e "$into_dir/$(basename "$item")" ]]; then
            print_colored "$COLOR_RED" "    Kept existing, skipped: memory/$(basename "$item")"
        else
            run mv "$item" "$into_dir/"
        fi
    done
    if [[ $APPLY -eq 1 ]]; then
        rmdir "$from_dir" 2>/dev/null || true
    fi
}

# Rewrite SOURCE_PATH to DEST_PATH inside one file, keeping its formatting.
rewrite_file() {
    local target_file=$1 pattern replacement temp_file
    pattern="$(escape_sed_pattern "$SOURCE_PATH")"
    replacement="$(escape_sed_replacement "$DEST_PATH")"
    temp_file=$(mktemp "$WORK_DIR/rewrite.XXXXXX")
    sed "s|${pattern}\([\"/]\)|${replacement}\1|g" "$target_file" > "$temp_file"
    # cat keeps the original file's inode and permissions.
    cat "$temp_file" > "$target_file"
    rm -f "$temp_file"
}

rewrite_app_metadata() {
    print_colored "$COLOR_BRIGHTYELLOW" "Step 4: rewrite desktop app session metadata and history"
    local target_file
    {
        files_with_reference "$APP_SESSIONS_DIR" 'local_*.json'
        file_has_reference "$HISTORY_FILE" && printf '%s\n' "$HISTORY_FILE"
        true
    } > "$WORK_DIR/rewrite-list"

    while IFS= read -r target_file; do
        print_colored "$COLOR_YELLOW" "  $(basename "$target_file")"
        if [[ $APPLY -eq 1 ]]; then
            rewrite_file "$target_file"
            case "$target_file" in
                *.json) jq empty "$target_file" || die "Invalid JSON after edit: $target_file" ;;
            esac
        fi
    done < "$WORK_DIR/rewrite-list"
}

merge_claude_json() {
    print_colored "$COLOR_BRIGHTYELLOW" "Step 5: remap project entries in ~/.claude.json"
    [[ -f "$CLAUDE_JSON" ]] || { print_colored "$COLOR_YELLOW" "  No ~/.claude.json"; return 0; }

    local moved_keys
    moved_keys=$(jq -r --arg s "$SOURCE_PATH" \
        '(.projects // {}) | keys[] | select(. == $s or startswith($s + "/"))' "$CLAUDE_JSON")
    if [[ -z "$moved_keys" ]]; then
        print_colored "$COLOR_YELLOW" "  No matching project entries"
        return 0
    fi
    printf '%s\n' "$moved_keys" | sed 's/^/  /'
    [[ $APPLY -eq 1 ]] || return 0

    # Moved entries merge into any existing DEST entry: DEST values win, and
    # allowedTools is the union of both.
    local jq_filter='
        def remap: if . == $s then $d
                   elif startswith($s + "/") then $d + .[($s | length):]
                   else . end;
        .projects as $projects
        | ($projects | with_entries(select(.key == $s or (.key | startswith($s + "/")) | not))) as $kept
        | .projects = (
            reduce ($projects | to_entries[]
                    | select(.key == $s or (.key | startswith($s + "/")))) as $entry
              ($kept;
               ($entry.key | remap) as $new_key
               | (.[$new_key] // {}) as $existing
               | .[$new_key] = (($entry.value + $existing)
                   | if ($entry.value.allowedTools or $existing.allowedTools)
                     then .allowedTools = ((($entry.value.allowedTools // []) + ($existing.allowedTools // [])) | unique)
                     else . end)))'
    local temp_file
    temp_file=$(mktemp "$WORK_DIR/claude-json.XXXXXX")
    jq --arg s "$SOURCE_PATH" --arg d "$DEST_PATH" "$jq_filter" "$CLAUDE_JSON" > "$temp_file"
    jq empty "$temp_file" || die "Merged JSON invalid; ~/.claude.json left untouched"
    cat "$temp_file" > "$CLAUDE_JSON"
    rm -f "$temp_file"
}

repair_git_worktrees() {
    print_colored "$COLOR_BRIGHTYELLOW" "Step 6: repair git worktree links"
    if [[ -d "$DEST_PATH/.git" ]]; then
        if [[ $APPLY -eq 1 ]]; then
            git -C "$DEST_PATH" worktree repair || print_colored "$COLOR_RED" "  worktree repair failed (non-fatal)"
        else
            printf '  [dry-run] git -C %q worktree repair\n' "$DEST_PATH"
        fi
    else
        print_colored "$COLOR_YELLOW" "  Not a git repository root, skipping"
    fi
}

report_other_references() {
    print_colored "$COLOR_BRIGHTYELLOW" "Other references under ~/.claude (reported, not modified)"
    local pattern found
    pattern="$(escape_sed_pattern "$SOURCE_PATH")[\"/]"
    found=$(grep -rl --exclude-dir=projects --exclude-dir=file-history --exclude=history.jsonl \
        -- "$pattern" "$CLAUDE_HOME" 2>/dev/null || true)
    if [[ -z "$found" ]]; then
        print_colored "$COLOR_YELLOW" "  None"
    else
        printf '%s\n' "$found" | sed 's/^/  /'
    fi
}

# --------------------------------------------------------------------------
# Verification
# --------------------------------------------------------------------------

VERIFY_FAILURES=0

# check "description" command [args...] - PASS when the command succeeds.
check() {
    local description=$1
    shift
    if "$@"; then
        print_colored "$COLOR_GREEN" "  PASS  $description"
    else
        print_colored "$COLOR_RED" "  FAIL  $description"
        VERIFY_FAILURES=$((VERIFY_FAILURES + 1))
    fi
}

negate() { ! "$@"; }

folder_only_at_dest() { [[ ! -e "$SOURCE_PATH" && -e "$DEST_PATH" ]]; }

no_leftover_project_dirs() {
    [[ -z "$(discover_project_dirs)" ]]
}

no_stale_metadata() {
    [[ -z "$(files_with_reference "$APP_SESSIONS_DIR" 'local_*.json')" ]]
}

all_metadata_valid_json() {
    local target_file
    [[ -d "$APP_SESSIONS_DIR" ]] || return 0
    while IFS= read -r target_file; do
        jq empty "$target_file" >/dev/null 2>&1 || return 1
    done < <(find "$APP_SESSIONS_DIR" -name 'local_*.json')
}

claude_json_valid() { [[ ! -f "$CLAUDE_JSON" ]] || jq empty "$CLAUDE_JSON" >/dev/null 2>&1; }

claude_json_has_no_source_entry() {
    [[ ! -f "$CLAUDE_JSON" ]] && return 0
    [[ -z "$(jq -r --arg s "$SOURCE_PATH" \
        '(.projects // {}) | keys[] | select(. == $s or startswith($s + "/"))' "$CLAUDE_JSON")" ]]
}

dest_project_dir_holds_files() {
    local new_project_dir after_count=0
    new_project_dir="$PROJECTS_DIR/$(encode_path "$DEST_PATH")"
    [[ -d "$new_project_dir" ]] || return 1
    if [[ -n "$BEFORE_FILE_COUNT" ]]; then
        # Count every destination dir the move produced, nested projects included.
        while IFS= read -r new_project_dir; do
            after_count=$((after_count + $(count_files_in "$new_project_dir")))
        done < <(cut -f2 "$WORK_DIR/pre-dirs" | sort -u)
        [[ "$after_count" -ge "$BEFORE_FILE_COUNT" ]] || return 1
    fi
}

verify_move() {
    print_colored "$COLOR_BRIGHTYELLOW" "Verifying move: $SOURCE_PATH -> $DEST_PATH"
    VERIFY_FAILURES=0
    check "folder exists only at DEST" folder_only_at_dest
    check "no project dirs left under the old encoded path" no_leftover_project_dirs
    check "no desktop metadata still names SOURCE" no_stale_metadata
    check "all desktop metadata files are valid JSON" all_metadata_valid_json
    check "~/.claude.json is valid JSON" claude_json_valid
    check "~/.claude.json has no project entry for SOURCE" claude_json_has_no_source_entry
    check "history.jsonl no longer names SOURCE" negate file_has_reference "$HISTORY_FILE"
    check "DEST project dir exists and holds every moved file (expected >= ${BEFORE_FILE_COUNT:-n/a})" \
        dest_project_dir_holds_files

    if [[ $VERIFY_FAILURES -eq 0 ]]; then
        print_colored "$COLOR_GREEN" "All checks passed."
        return 0
    fi
    print_colored "$COLOR_RED" "$VERIFY_FAILURES check(s) failed."
    return 1
}

# --------------------------------------------------------------------------
# Backup management
# --------------------------------------------------------------------------

list_backups() {
    [[ -d "$BACKUP_ROOT" ]] || { print_colored "$COLOR_YELLOW" "No backups ($BACKUP_ROOT does not exist)"; return 0; }
    local backup_dir found=0
    for backup_dir in "$BACKUP_ROOT"/*/; do
        [[ -d "$backup_dir" ]] || continue
        found=1
        printf '%s\t%s\t%s -> %s\n' "$(basename "$backup_dir")" \
            "$(du -sh "$backup_dir" | cut -f1)" \
            "$(awk -F'\t' '$1=="source"{print $2}' "$backup_dir/info.tsv" 2>/dev/null)" \
            "$(awk -F'\t' '$1=="dest"{print $2}' "$backup_dir/info.tsv" 2>/dev/null)"
    done
    [[ $found -eq 1 ]] || print_colored "$COLOR_YELLOW" "No backups"
}

# Refuse anything that is not a direct child of BACKUP_ROOT.
safe_backup_path() {
    local backup_name=$1
    case "$backup_name" in
        ""|.|..|*/*) die "Invalid backup name: $backup_name" ;;
    esac
    [[ -d "$BACKUP_ROOT/$backup_name" ]] || die "No such backup: $backup_name"
    printf '%s' "$BACKUP_ROOT/$backup_name"
}

remove_backup() {
    local backup_path
    backup_path=$(safe_backup_path "$1")
    run rm -rf -- "$backup_path"
}

clean_backups() {
    local retention_days=${1:-$DEFAULT_RETENTION_DAYS}
    [[ "$retention_days" =~ ^[0-9]+$ ]] || die "DAYS must be a number: $retention_days"
    [[ -d "$BACKUP_ROOT" ]] || { print_colored "$COLOR_YELLOW" "No backups"; return 0; }
    local backup_path removed=0
    while IFS= read -r backup_path; do
        removed=$((removed + 1))
        run rm -rf -- "$backup_path"
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime "+$retention_days")
    print_colored "$COLOR_YELLOW" "$removed backup(s) older than $retention_days day(s)"
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

parse_arguments() {
    local positional_count=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --apply) APPLY=1 ;;
            -h|--help) usage; exit 0 ;;
            --verify) MODE="verify" ;;
            --list-backups) MODE="list" ;;
            --clean-backups)
                MODE="clean"
                if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then MODE_ARGUMENT=$2; shift; fi
                ;;
            --remove-backup)
                [[ $# -gt 1 ]] || die "--remove-backup needs a backup name"
                MODE="remove"; MODE_ARGUMENT=$2; shift
                ;;
            -*) usage; die "Unknown option: $1" ;;
            *)
                positional_count=$((positional_count + 1))
                if [[ $positional_count -eq 1 ]]; then SOURCE_PATH=$1
                elif [[ $positional_count -eq 2 ]]; then DEST_PATH=$1
                else die "Too many arguments"
                fi
                ;;
        esac
        shift
    done

    case "$MODE" in
        move|verify)
            [[ -n "$SOURCE_PATH" && -n "$DEST_PATH" ]] || { usage; die "SOURCE and DEST are required"; }
            SOURCE_PATH=$(normalize_path "$SOURCE_PATH")
            DEST_PATH=$(normalize_path "$DEST_PATH")
            [[ "$SOURCE_PATH" != "$DEST_PATH" ]] || die "SOURCE and DEST are the same"
            case "$DEST_PATH/" in
                "$SOURCE_PATH"/*) die "DEST cannot be inside SOURCE" ;;
            esac
            ;;
    esac
}

main() {
    parse_arguments "$@"
    command -v jq >/dev/null || die "jq is required (brew install jq)"
    WORK_DIR=$(mktemp -d)
    trap cleanup_work_dir EXIT

    case "$MODE" in
        list) list_backups; return 0 ;;
        clean) clean_backups "$MODE_ARGUMENT"; return 0 ;;
        remove) remove_backup "$MODE_ARGUMENT"; return 0 ;;
        verify) verify_move; return $? ;;
    esac

    check_claude_not_running
    [[ $APPLY -eq 1 ]] || print_colored "$COLOR_BRIGHTYELLOW" "DRY RUN - no changes will be made"

    # Record how many transcript files exist now so verify can prove none were lost.
    discover_project_dirs > "$WORK_DIR/pre-dirs"
    BEFORE_FILE_COUNT=0
    local pre_old pre_new
    while IFS=$'\t' read -r pre_old pre_new; do
        [[ -n "$pre_old" ]] && BEFORE_FILE_COUNT=$((BEFORE_FILE_COUNT + $(count_files_in "$pre_old")))
    done < "$WORK_DIR/pre-dirs"
    [[ -s "$WORK_DIR/pre-dirs" ]] || BEFORE_FILE_COUNT=""

    backup_state
    move_folder
    move_project_dirs
    rewrite_app_metadata
    merge_claude_json
    repair_git_worktrees
    report_other_references

    if [[ $APPLY -eq 1 ]]; then
        verify_move || die "Verification failed; backup kept at $BACKUP_DIR"
        print_colored "$COLOR_GREEN" "Done. Reopen the Claude app."
        print_colored "$COLOR_GREEN" "Backup kept at: $BACKUP_DIR"
        print_colored "$COLOR_GREEN" "Once you are satisfied, remove it with:"
        print_colored "$COLOR_GREEN" "  $0 --apply --remove-backup $(basename "$BACKUP_DIR")"
    else
        print_colored "$COLOR_GREEN" "Dry run complete. Re-run with --apply after quitting Claude."
    fi
}

main "$@"
