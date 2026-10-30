#!/usr/bin/env bash
# check() evals its condition string, so the single quotes and the variables
# only read inside those strings are intentional.
# shellcheck disable=SC2016,SC2034
# Fixture test for brew-receipt-audit.sh and brew-receipt-hook.sh against a stub
# `brew` on PATH. The stub serves canned `brew info --json=v2 --installed` and
# `brew linkage` output and records every reinstall/uninstall instead of
# running it, so nothing touches the real Homebrew installation.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"; WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
AUDIT="$SCRIPT_DIR/brew-receipt-audit.sh"; HOOK="$SCRIPT_DIR/brew-receipt-hook.sh"
export HOME="$WORK/home" PATH="$WORK/bin:$PATH" STATE="$WORK/state" NO_COLOR=1
mkdir -p "$HOME" "$WORK/bin" "$STATE"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

cat > "$WORK/bin/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    info)      cat "$STATE/info.json" ;;
    linkage)   cat "$STATE/linkage.txt" ;;
    reinstall)
        echo "reinstall ${*:2}${HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK:+ (dependents-check-off)}" >> "$STATE/calls"
        # A chain test stages an intermediate world for the first reinstall.
        if [[ -f "$STATE/info.after-first-reinstall.json" ]]; then
            mv "$STATE/info.after-first-reinstall.json" "$STATE/info.json"
        elif [[ -f "$STATE/info.fixed.json" ]]; then
            cp "$STATE/info.fixed.json" "$STATE/info.json"
        fi ;;
    uninstall) echo "uninstall ${*:2}" >> "$STATE/calls" ;;
    upgrade)   echo "upgrade ${*:2}" >> "$STATE/calls"; exit "${STUB_UPGRADE_STATUS:-0}" ;;
    *)         exit 0 ;;
esac
STUB
chmod +x "$WORK/bin/brew"

# formula NAME DEPS-JSON RECEIPT-JSON [outdated] [on_request]
formula() {
    jq -n --arg name "$1" --argjson deps "$2" --argjson receipt "$3" \
        --argjson outdated "${4:-false}" --argjson on_request "${5:-false}" '{
        name: $name, full_name: $name, aliases: [], oldnames: [],
        dependencies: $deps, recommended_dependencies: [], optional_dependencies: [],
        uses_from_macos: [], outdated: $outdated, linked_keg: "1.0",
        installed: [{version: "1.0", installed_on_request: $on_request,
                     runtime_dependencies: ($receipt | map({full_name: .}))}]}'
}
# world FILE FORMULA-JSON...
world() { local file=$1; shift; printf '%s\n' "$@" | jq -s '{formulae: ., casks: []}' > "$file"; }

# The icu4c@78 case: simdutf moved to icu4c@79; ada-url and merve kept @78.
stale_world() {
    world "$STATE/info.json" \
        "$(formula node '["ada-url","merve"]' '["ada-url","merve","simdutf","icu4c@79"]' false true)" \
        "$(formula ada-url '["simdutf"]' '["simdutf","icu4c@78"]')" \
        "$(formula merve '["simdutf"]' '["simdutf","icu4c@78"]')" \
        "$(formula simdutf '["icu4c@79"]' '["icu4c@79"]')" \
        "$(formula icu4c@79 '[]' '[]')" \
        "$(formula icu4c@78 '[]' '[]')"
    world "$STATE/info.fixed.json" \
        "$(formula node '["ada-url","merve"]' '["ada-url","merve","simdutf","icu4c@79"]' false true)" \
        "$(formula ada-url '["simdutf"]' '["simdutf","icu4c@79"]')" \
        "$(formula merve '["simdutf"]' '["simdutf","icu4c@79"]')" \
        "$(formula simdutf '["icu4c@79"]' '["icu4c@79"]')" \
        "$(formula icu4c@79 '[]' '[]')" \
        "$(formula icu4c@78 '[]' '[]')"
    printf '==> Checking simdutf linkage\nHomebrew libraries:\n  /opt/homebrew/opt/icu4c@79/lib/libicuuc.79.dylib (icu4c@79)\n' > "$STATE/linkage.txt"
    : > "$STATE/calls"
}

echo "== audit"
stale_world; cp "$STATE/info.fixed.json" "$STATE/info.json"
out=$("$AUDIT" --quiet </dev/null); rc=$?
check "clean: exit 0, --quiet prints nothing" '[[ $rc -eq 0 && -z "$out" ]]'

stale_world
out=$("$AUDIT" --dry-run </dev/null); rc=$?
check "dry run: reports ada-url and merve" '[[ "$out" == *"ada-url: icu4c@78"* && "$out" == *"merve: icu4c@78"* ]]'
check "dry run: exit 1, nothing run" '[[ $rc -eq 1 && ! -s "$STATE/calls" ]]'

stale_world
out=$("$AUDIT" </dev/null); rc=$?
check "no terminal, no --yes: nothing run" '[[ $rc -eq 1 && ! -s "$STATE/calls" && "$out" == *"No terminal"* ]]'

# Answer the audit's prompts on a pseudo-terminal, since it asks only when
# stdin is a terminal. $1 holds one answer per prompt, separated by "\n"; an
# empty answer just presses Return, and prompts beyond the list get Ctrl-D.
# The exit status is the audit's own.
answering() {
    local answers=$1; shift
    ANSWERS="$answers" expect -f - "$AUDIT" "$@" <<'EXPECT'
log_user 1
set timeout 20
set answers [split [string map {"\\n" "\n"} $env(ANSWERS)] "\n"]
spawn -noecho {*}$argv
expect {
    -re {\[[Yy]/[Nn]\]: $} {
        if {[llength $answers] > 0} {
            send -- "[lindex $answers 0]\r"
            set answers [lrange $answers 1 end]
        } else {
            send -- "\004"
        }
        exp_continue
    }
    eof
}
lassign [wait] pid spawn_id os_error status
exit $status
EXPECT
}

stale_world
out=$("$AUDIT" --yes --log </dev/null); rc=$?
check "--yes: reinstalls both, with the dependents check off" 'grep -qx "reinstall --formula ada-url merve (dependents-check-off)" "$STATE/calls"'
check "--yes: lists freed icu4c@78 but does not uninstall" '[[ "$out" == *"No longer needed"*"icu4c@78"* ]] && ! grep -q "^uninstall" "$STATE/calls"'
check "--yes: exit 0" '[[ $rc -eq 0 ]]'
log="$HOME/Library/Logs/brew-receipt-audit.log"
check "--log: one receipt line per reinstalled formula" '[[ $(grep -c $'"'"'\treceipt\t.*\treinstalled$'"'"' "$log") -eq 2 ]]'

stale_world; rm -f "$log"
out=$(answering 'y\ny' --log); rc=$?
check "prompted: yes, yes reinstalls and uninstalls icu4c@78" 'grep -qx "uninstall --formula icu4c@78" "$STATE/calls" && [[ $rc -eq 0 ]]'
check "--log: removal line" 'grep -q $'"'"'\tremoval\ticu4c@78\t'"'"' "$log"'

stale_world
out=$(answering 'y\n'); rc=$?
check "prompted: uninstall defaults to no" 'grep -q "^reinstall" "$STATE/calls" && ! grep -q "^uninstall" "$STATE/calls"'

stale_world
out=$(answering ''); rc=$?
check "prompted: end of input is no" '[[ $rc -eq 1 && ! -s "$STATE/calls" ]]'

# Add a formula to both the before and after worlds, so icu4c@78 stays needed
# by something other than the stale receipts.
also_installed() {
    local extra=$1 file
    for file in "$STATE/info.json" "$STATE/info.fixed.json"; do
        jq --argjson extra "$extra" '.formulae += [$extra]' "$file" > "$file.new" && mv "$file.new" "$file"
    done
}
stale_world; also_installed "$(formula php '[]' '["icu4c@78"]')"
out=$(answering 'y\ny'); rc=$?
check "kept: named in another formula's receipt" 'grep -q "^reinstall" "$STATE/calls" && ! grep -q "^uninstall" "$STATE/calls"'

stale_world; also_installed "$(formula php '["icu4c@78"]' '[]')"
out=$(answering 'y\ny'); rc=$?
check "kept: declared by another formula" 'grep -q "^reinstall" "$STATE/calls" && ! grep -q "^uninstall" "$STATE/calls"'

stale_world; also_installed "$(formula php '[]' '[]')"
printf '==> Checking php linkage\nHomebrew libraries:\n  /opt/homebrew/opt/icu4c@78/lib/libicuuc.78.dylib (icu4c@78)\n' >> "$STATE/linkage.txt"
out=$(answering 'y\ny'); rc=$?
check "kept: linked by another keg" 'grep -q "^reinstall" "$STATE/calls" && ! grep -q "^uninstall" "$STATE/calls"'

stale_world
for file in "$STATE/info.json" "$STATE/info.fixed.json"; do
    jq '.casks = [{token: "some-app", depends_on: {formula: ["icu4c@78"]}}]' "$file" > "$file.new" && mv "$file.new" "$file"
done
out=$(answering 'y\ny'); rc=$?
check "kept: a cask depends on it" 'grep -q "^reinstall" "$STATE/calls" && ! grep -q "^uninstall" "$STATE/calls"'

stale_world
world "$STATE/info.json" \
    "$(formula ada-url '["simdutf"]' '["simdutf","icu4c@78"]' true)" \
    "$(formula simdutf '["icu4c@79"]' '["icu4c@79"]')" \
    "$(formula icu4c@79 '[]' '[]')" "$(formula icu4c@78 '[]' '[]')"
out=$("$AUDIT" --yes </dev/null); rc=$?
check "outdated formula: reported, not reinstalled" '[[ $rc -eq 1 && "$out" == *"outdated"* ]] && ! grep -q "^reinstall" "$STATE/calls"'

stale_world
world "$STATE/info.json" \
    "$(formula webp '["libpng"]' '["libpng","libtiff"]')" \
    "$(formula libpng '[]' '[]')" "$(formula libtiff '[]' '[]')"
printf '==> Checking webp linkage\nHomebrew libraries:\n  /opt/homebrew/opt/libtiff/lib/libtiff.6.dylib (libtiff)\n' > "$STATE/linkage.txt"
out=$("$AUDIT" --quiet </dev/null); rc=$?
check "linked but undeclared dependency is not stale" '[[ $rc -eq 0 && -z "$out" ]]'

stale_world
world "$STATE/info.json" \
    "$(formula ada-url '["simdutf"]' '["simdutf","icu4c@78"]')" \
    "$(formula simdutf '["icu4c@79"]' '["icu4c@79"]')" \
    "$(formula icu4c@79 '[]' '[]')" "$(formula icu4c@78 '[]' '[]' false true)"
jq '(.formulae[] | select(.name == "ada-url") | .installed[0].runtime_dependencies) = [{full_name: "simdutf"}, {full_name: "icu4c@79"}]' \
    "$STATE/info.json" > "$STATE/info.fixed.json"
out=$(answering 'y\ny'); rc=$?
check "kept: installed on request" '[[ $rc -eq 0 ]] && ! grep -q "^uninstall" "$STATE/calls"'

stale_world; rm "$STATE/info.fixed.json"
out=$("$AUDIT" --yes </dev/null); rc=$?
check "reinstall that changes nothing: stops, exit 1" '[[ $rc -eq 1 && $(grep -c "^reinstall" "$STATE/calls") -eq 1 ]]'

stale_world
world "$STATE/info.json" \
    "$(formula ada-url '["simdutf"]' '["simdutf","icu4c@78"]')" \
    "$(formula simdutf '["icu4c@79"]' '["icu4c@79"]' true)" \
    "$(formula icu4c@79 '[]' '[]')" "$(formula icu4c@78 '[]' '[]')"
out=$("$AUDIT" --yes </dev/null); rc=$?
check "outdated dependency: reported, not reinstalled" '[[ $rc -eq 1 && "$out" == *"depends on outdated simdutf"* ]] && ! grep -q "^reinstall" "$STATE/calls"'

# A chain: lib's receipt is stale, and app inherits the entry through lib's
# receipt, so app is only flagged once lib has been reinstalled.
stale_world
world "$STATE/info.json" \
    "$(formula app '["lib"]' '["lib","old"]')" "$(formula lib '["new"]' '["old"]')" \
    "$(formula new '[]' '[]')" "$(formula old '[]' '[]')"
world "$STATE/info.lib-fixed.json" \
    "$(formula app '["lib"]' '["lib","old"]')" "$(formula lib '["new"]' '["new"]')" \
    "$(formula new '[]' '[]')" "$(formula old '[]' '[]')"
world "$STATE/info.fixed.json" \
    "$(formula app '["lib"]' '["lib","new"]')" "$(formula lib '["new"]' '["new"]')" \
    "$(formula new '[]' '[]')" "$(formula old '[]' '[]')"
: > "$STATE/linkage.txt"
cp "$STATE/info.lib-fixed.json" "$STATE/info.after-first-reinstall.json"
out=$("$AUDIT" --yes </dev/null); rc=$?
check "chain: second pass reinstalls the dependent" '[[ $rc -eq 0 ]] && grep -qx "reinstall --formula lib (dependents-check-off)" "$STATE/calls" && grep -qx "reinstall --formula app (dependents-check-off)" "$STATE/calls"'
rm -f "$STATE/info.after-first-reinstall.json"

# Tap formulae: brew linkage prints the short name, receipts the full one.
stale_world
world "$STATE/info.json" \
    "$(formula user/tap/foo '["libpng"]' '["libpng","libtiff"]')" \
    "$(formula libpng '[]' '[]')" "$(formula libtiff '[]' '[]')"
jq '(.formulae[] | select(.full_name == "user/tap/foo")) |= (.name = "foo")' "$STATE/info.json" > "$STATE/info.new" && mv "$STATE/info.new" "$STATE/info.json"
printf '==> Checking foo linkage\nHomebrew libraries:\n  /opt/homebrew/opt/libtiff/lib/libtiff.6.dylib (libtiff)\n' > "$STATE/linkage.txt"
out=$("$AUDIT" --quiet </dev/null); rc=$?
check "tap formula: linkage matched by short name" '[[ $rc -eq 0 && -z "$out" ]]'

# Old names and aliases resolve to the installed formula.
stale_world
world "$STATE/info.json" \
    "$(formula app '["oldlib"]' '["newlib"]')" "$(formula newlib '[]' '[]')"
jq '(.formulae[] | select(.name == "newlib") | .oldnames) = ["oldlib"]' "$STATE/info.json" > "$STATE/info.new" && mv "$STATE/info.new" "$STATE/info.json"
out=$("$AUDIT" --quiet </dev/null); rc=$?
check "old name in the formula resolves to the installed one" '[[ $rc -eq 0 && -z "$out" ]]'

stale_world; printf 'not json' > "$STATE/info.json"
out=$("$AUDIT" --quiet 2>&1 </dev/null); rc=$?
check "unreadable brew info: exit 2 with an error, not all-clear" '[[ $rc -eq 2 && "$out" == *"ERROR"* ]]'

echo "== hook"
cat > "$WORK/bin/fake-audit" <<'FAKE'
#!/usr/bin/env bash
echo "audit $*" >> "$STATE/calls"
FAKE
chmod +x "$WORK/bin/fake-audit"
hook_run() {
    : > "$STATE/calls"
    BREW_RECEIPT_AUDIT="$WORK/bin/fake-audit" zsh -f -c "$1"
}
hook_run "source '$HOOK'; brew upgrade jq"
check "upgrade runs the audit after brew" '[[ "$(cat "$STATE/calls")" == $'"'"'upgrade jq\naudit --quiet --log'"'"' ]]'
hook_run "source '$HOOK'; brew upgrade --dry-run; brew upgrade -n; brew upgrade --cask x; brew list"
check "dry run, -n, --cask and other commands skip it" '! grep -q "^audit" "$STATE/calls"'
hook_run "source '$HOOK'; source '$HOOK'; brew upgrade"
check "sourcing twice audits once" '[[ $(grep -c "^audit" "$STATE/calls") -eq 1 ]]'
STUB_UPGRADE_STATUS=3 hook_run "source '$HOOK'; brew upgrade; exit \$?"; rc=$?
check "brew's exit status is kept and the audit still runs" '[[ $rc -eq 3 ]] && grep -q "^audit" "$STATE/calls"'
hook_run "brew() { echo \"inner \$*\" >> \"\$STATE/calls\"; }; source '$HOOK'; brew upgrade jq"
check "wraps an existing brew() such as homebrew.sh" '[[ "$(cat "$STATE/calls")" == $'"'"'inner upgrade jq\naudit --quiet --log'"'"' ]]'

exit $fail
