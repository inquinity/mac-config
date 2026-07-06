load_setting_from_keychain() {
    local export_name="$1"
    local service_name
    local current_value
    local setting_value

    if [[ -z "$export_name" ]]; then
        printf "usage: load_setting_from_keychain EXPORT_NAME\n"
        return 2
    fi

    current_value="${(P)export_name}"
    if [[ -n "$current_value" ]]; then
        return 0
    fi

    service_name="$(keychain_service_name "$export_name")"
    if ! setting_value=$(security find-generic-password -w -s "$service_name" -a default 2>/dev/null); then
        printf "setting not found: %s\n" "$export_name"
        return 1
    fi

    export "$export_name=$setting_value"
}
