#!/bin/zsh
# hotspot — connect to a (possibly hidden) Wi-Fi network using a password
# stored in the macOS keychain. Designed for personal mobile hotspots whose
# SSID is not broadcast or appears late.

set -euo pipefail

# --- color helpers ---------------------------------------------------------
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_MAGENTA="\e[35m"
COLOR_CYAN="\e[36m"
COLOR_BLUE="\e[34m"
COLOR_BRIGHTYELLOW="\e[93m"
COLOR_RESET="\e[0m"

print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

# --- defaults --------------------------------------------------------------
default_ssid="SecNet97"
max_attempts=12
attempt_sleep_seconds=5
dry_run=0
debug=0
save_mode=0
reset_mode=0

# Export-name prefix for keychain lookups. Combined with a sanitized SSID
# this yields e.g. WIFI_PW_SECNET97, which load_setting_from_keychain maps
# to keychain service "env/wifi_pw_secnet97", account "default".
keychain_export_prefix="WIFI_PW"

# --- usage -----------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${0##*/} [options] [ssid]

Connects to a Wi-Fi network whose password is stored in the macOS keychain.
Retries until the network appears or the attempt budget is exhausted —
useful for mobile hotspots that take a few seconds to start broadcasting.

Positional:
  ssid                  SSID to join (default: ${default_ssid})

Options:
      --save            Prompt for the password and store it in your login
                        keychain via save_setting_in_keychain. Run this once
                        per SSID before normal use.
      --reset           Delete saved password(s) for the SSID — both the
                        login-keychain entry created by --save and any
                        legacy entry in /Library/Keychains/System.keychain
                        (the System entry triggers a GUI admin prompt).
  -n, --dry-run         Show what would happen; do not change Wi-Fi state.
      --debug           Print extra diagnostic output.
      --tries N         Connection attempts before giving up (default: ${max_attempts}).
      --sleep N         Seconds to wait between attempts (default: ${attempt_sleep_seconds}).
  -h, --help            Show this help and exit.

Examples:
  ${0##*/} --save                One-time: capture the password for SecNet97.
  ${0##*/} --save CoffeeShopGuest  Capture the password for a different SSID.
  ${0##*/}                       Join the default hotspot.
  ${0##*/} CoffeeShopGuest       Join a specific saved network.
  ${0##*/} --dry-run SecNet97    Preview without changing state.
  ${0##*/} --reset SecNet97      Forget the saved password for an SSID.

Keychain:
  Passwords are read via load_setting_from_keychain (from ~/.zshenv).
  SSID 'SecNet97' is looked up as export ${keychain_export_prefix}_SECNET97,
  which maps to keychain service 'env/wifi_pw_secnet97', account 'default'.
EOF
}

# --- helpers ---------------------------------------------------------------
require_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_colored "$COLOR_RED" "required command not found: $cmd"
        exit 1
    fi
}

# Asserts that a zsh function (typically defined in ~/.zshenv) is in scope.
require_function() {
    local fn=$1
    if (( ! ${+functions[$fn]} )); then
        print_colored "$COLOR_RED" "required zsh function not loaded: $fn"
        print_colored "$COLOR_YELLOW" "expected to be defined in ~/.zshenv (auto-loaded for all zsh invocations)."
        exit 1
    fi
}

debug_log() {
    (( debug )) || return 0
    print_colored "$COLOR_CYAN" "[debug] $1"
}

# Returns the BSD name of the first Wi-Fi hardware port (e.g. en0).
find_wifi_interface() {
    networksetup -listallhardwareports \
        | awk '/Hardware Port: Wi-Fi/ { getline; print $2; exit }'
}

# Maps an SSID to the export-name convention used by save/load_setting_in_keychain.
# Non-alphanumerics become underscores so the result is a valid shell identifier.
ssid_to_export_name() {
    local ssid=$1
    local sanitized=${ssid//[^A-Za-z0-9]/_}
    printf "%s_%s" "$keychain_export_prefix" "${(U)sanitized}"
}

# Fetches the saved password for an SSID using load_setting_from_keychain.
# Stdout: password on hit; empty on miss. Always returns 0.
#
# Pre-sets the target export to empty (not unset) so:
#   1. load_setting_from_keychain reads fresh from keychain rather than
#      short-circuiting on a value inherited from the parent shell.
#   2. Its internal `${(P)export_name}` access doesn't trip NO_UNSET (set -u).
fetch_keychain_password() {
    local ssid=$1
    local export_name
    export_name=$(ssid_to_export_name "$ssid")
    typeset -g "$export_name"=""
    if ! load_setting_from_keychain "$export_name" >/dev/null 2>&1; then
        unset "$export_name"
        return 0
    fi
    printf "%s" "${(P)export_name}"
    unset "$export_name"
}

# Drives save_setting_in_keychain interactively to capture the password for an SSID.
save_password_for_ssid() {
    local ssid=$1
    local export_name
    export_name=$(ssid_to_export_name "$ssid")
    print_colored "$COLOR_BRIGHTYELLOW" \
        "saving password for '$ssid' as keychain entry for \$$export_name"
    save_setting_in_keychain "$export_name"
}

# Deletes saved passwords for an SSID from both keychains where macOS may
# have stored them. Honors $dry_run. Returns 0 even if nothing was found
# (idempotent), but returns non-zero on a real delete failure.
reset_password_for_ssid() {
    local ssid=$1
    local export_name service_name
    export_name=$(ssid_to_export_name "$ssid")
    service_name="env/${(L)export_name}"
    local found_anything=0

    # 1. login keychain — the entry created by --save (service "env/wifi_pw_<ssid>").
    if security find-generic-password -s "$service_name" -a default >/dev/null 2>&1; then
        if (( dry_run )); then
            print_colored "$COLOR_BRIGHTYELLOW" \
                "dry run: would delete login keychain entry '$service_name' (account: default)"
        else
            if security delete-generic-password -s "$service_name" -a default >/dev/null 2>&1; then
                print_colored "$COLOR_GREEN" "deleted login keychain entry '$service_name'"
            else
                print_colored "$COLOR_RED" "failed to delete login keychain entry '$service_name'"
                return 1
            fi
        fi
        found_anything=1
    else
        debug_log "no login keychain entry at service '$service_name'"
    fi

    # 2. System keychain — the entry macOS creates when you join via System Settings.
    # Service is the raw SSID. Delete triggers a GUI admin auth prompt.
    if security find-generic-password -s "$ssid" \
            /Library/Keychains/System.keychain >/dev/null 2>&1; then
        if (( dry_run )); then
            print_colored "$COLOR_BRIGHTYELLOW" \
                "dry run: would delete System keychain entry for '$ssid' (admin auth would be required)"
        else
            print_colored "$COLOR_BRIGHTYELLOW" \
                "deleting System keychain entry for '$ssid' (admin auth required)..."
            if security delete-generic-password -s "$ssid" \
                    /Library/Keychains/System.keychain >/dev/null 2>&1; then
                print_colored "$COLOR_GREEN" "deleted System keychain entry for '$ssid'"
            else
                print_colored "$COLOR_RED" "failed to delete System keychain entry for '$ssid'"
                return 1
            fi
        fi
        found_anything=1
    else
        debug_log "no System keychain entry for '$ssid'"
    fi

    if (( ! found_anything )); then
        print_colored "$COLOR_YELLOW" "no keychain entries found for '$ssid' — nothing to reset"
    fi
    return 0
}

# Returns the SSID the interface is currently joined to (may be empty).
# NOTE: returns empty when Location Services is denied for the calling
# terminal app, even when actually associated. See verify_joined() below.
current_ssid() {
    local interface=$1
    networksetup -getairportnetwork "$interface" \
        | awk -F': ' '/Current Wi-Fi Network/ { print $2 }'
}

# Returns 0 if the interface appears to be joined to the target SSID.
#
# Verification strategy, in order:
#   1. SSID readback matches  -> confirmed.
#   2. SSID readback is a *different* non-empty value -> wrong network, fail.
#   3. SSID readback is empty (Location Services denied) -> fall back to
#      "does the interface have an IPv4?" Strong enough signal given that
#      we just commanded the join ourselves a moment ago.
verify_joined() {
    local interface=$1 target_ssid=$2
    local current
    current=$(current_ssid "$interface")

    if [[ "$current" == "$target_ssid" ]]; then
        debug_log "verified by SSID readback: '$current'"
        return 0
    fi

    if [[ -n "$current" ]]; then
        debug_log "associated with '$current', not '$target_ssid'"
        return 1
    fi

    local ip
    ip=$(ipconfig getifaddr "$interface" 2>/dev/null || true)
    if [[ -n "$ip" ]]; then
        debug_log "SSID readback unavailable (Location Services?); interface has IP $ip"
        return 0
    fi

    debug_log "no SSID readback and no IPv4 on $interface yet"
    return 1
}

# Attempts a single connection. Prints networksetup's message (if any).
attempt_join() {
    local interface=$1 ssid=$2 password=$3
    networksetup -setairportnetwork "$interface" "$ssid" "$password" 2>&1 || true
}

# --- argument parsing ------------------------------------------------------
ssid=""
while (( $# )); do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        --save)       save_mode=1; shift ;;
        --reset)      reset_mode=1; shift ;;
        -n|--dry-run) dry_run=1; shift ;;
        --debug)      debug=1; shift ;;
        --tries)      max_attempts=$2; shift 2 ;;
        --sleep)      attempt_sleep_seconds=$2; shift 2 ;;
        --)           shift; break ;;
        -*)
            print_colored "$COLOR_RED" "unknown option: $1"
            usage
            exit 2
            ;;
        *)
            if [[ -z "$ssid" ]]; then
                ssid=$1
            else
                print_colored "$COLOR_RED" "unexpected argument: $1"
                usage
                exit 2
            fi
            shift
            ;;
    esac
done
ssid=${ssid:-$default_ssid}

# --- validation ------------------------------------------------------------
require_command networksetup
require_command security
require_command awk
require_function load_setting_from_keychain
require_function save_setting_in_keychain

if ! [[ "$max_attempts" =~ ^[0-9]+$ ]] || (( max_attempts < 1 )); then
    print_colored "$COLOR_RED" "--tries must be a positive integer"
    exit 2
fi
if ! [[ "$attempt_sleep_seconds" =~ ^[0-9]+$ ]]; then
    print_colored "$COLOR_RED" "--sleep must be a non-negative integer"
    exit 2
fi

if (( save_mode && reset_mode )); then
    print_colored "$COLOR_RED" "--save and --reset are mutually exclusive"
    exit 2
fi

# --- save / reset modes ----------------------------------------------------
# Handled before interface discovery so they work even when Wi-Fi hardware
# isn't available (e.g. preparing on a different machine, or scrubbing
# leftover credentials after a network is decommissioned).
if (( save_mode )); then
    save_password_for_ssid "$ssid"
    exit $?
fi

if (( reset_mode )); then
    reset_password_for_ssid "$ssid"
    exit $?
fi

wifi_interface=$(find_wifi_interface)
if [[ -z "$wifi_interface" ]]; then
    print_colored "$COLOR_RED" "no Wi-Fi interface found"
    exit 1
fi
debug_log "Wi-Fi interface: $wifi_interface"

password=$(fetch_keychain_password "$ssid")
if [[ -z "$password" ]]; then
    print_colored "$COLOR_RED" "no keychain entry for SSID '$ssid'"
    print_colored "$COLOR_YELLOW" "capture it once with: ${0##*/} --save${ssid:+ $ssid}"
    exit 1
fi
debug_log "found keychain password for '$ssid' (${#password} chars)"

# --- main ------------------------------------------------------------------
if (( dry_run )); then
    print_colored "$COLOR_BRIGHTYELLOW" "dry run: would join '$ssid' on $wifi_interface"
    print_colored "$COLOR_YELLOW" "retry budget: $max_attempts attempts, ${attempt_sleep_seconds}s apart"
    exit 0
fi

print_colored "$COLOR_BRIGHTYELLOW" "ensuring Wi-Fi power is on..."
networksetup -setairportpower "$wifi_interface" on >/dev/null

print_colored "$COLOR_BRIGHTYELLOW" \
    "joining '$ssid' on $wifi_interface (up to $max_attempts attempts)..."

for (( attempt = 1; attempt <= max_attempts; attempt++ )); do
    debug_log "attempt $attempt/$max_attempts"
    join_output=$(attempt_join "$wifi_interface" "$ssid" "$password")
    [[ -n "$join_output" ]] && debug_log "networksetup: $join_output"

    # Association + DHCP can take several seconds after networksetup returns;
    # poll a few times per attempt before falling back to the inter-attempt sleep.
    verified=0
    for (( probe = 1; probe <= 4; probe++ )); do
        sleep 2
        if verify_joined "$wifi_interface" "$ssid"; then
            verified=1
            break
        fi
        debug_log "probe $probe/4: not joined yet"
    done

    if (( verified )); then
        print_colored "$COLOR_GREEN" \
            "joined '$ssid' on $wifi_interface (attempt $attempt)"
        exit 0
    fi

    if (( attempt < max_attempts )); then
        debug_log "retrying in ${attempt_sleep_seconds}s"
        sleep "$attempt_sleep_seconds"
    fi
done

print_colored "$COLOR_RED" "could not join '$ssid' after $max_attempts attempts"
print_colored "$COLOR_YELLOW" "is the hotspot actually broadcasting? re-run with --debug for details."
exit 1