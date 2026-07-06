save_setting_in_keychain() {
    local export_name="$1"
    local service_name
    local setting_value

    if [[ -z "$export_name" ]]; then
        printf "usage: save_setting_in_keychain EXPORT_NAME\n"
        return 2
    fi

    service_name="$(keychain_service_name "$export_name")"
    read -s "setting_value?${export_name}: "
    echo

    if [[ -z "$setting_value" ]]; then
        printf "value is empty: %s\n" "$export_name"
        return 2
    fi

    security add-generic-password -U -s "$service_name" -a default -w "$setting_value"
    unset setting_value
}
