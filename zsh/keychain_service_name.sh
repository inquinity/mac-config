keychain_service_name() {
    local export_name="$1"
    printf "env/%s" "${(L)export_name}"
}
