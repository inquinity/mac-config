# brew-receipt-hook.sh
#
# Runs brew-receipt-audit.sh after every `brew upgrade`, so formulae whose
# install receipt still records a dependency they no longer need are found and
# reinstalled while the upgrade is fresh in mind -- the case where brew doctor
# reports a deprecated keg (icu4c@78, openssl@3) as "in use" by formulae that
# no longer link against it.
#
# zsh only: it wraps whatever `brew` is defined when it is sourced, so source
# it after homebrew.sh when that wrapper is used. The cool-off routing then
# still happens first and the audit runs once the upgrade has finished.
# Sourcing it again (e.g. re-sourcing ~/.zshrc) is a no-op rather than wrapping
# the wrapper.
#
# The audit only runs for a real upgrade: not for `--dry-run`/`-n`, not for
# `--cask`, which leaves formula receipts alone, and not after Ctrl-C. It
# runs even when the upgrade fails part-way, since the formulae that did
# upgrade can still leave stale receipts behind. brew's own exit status is
# what the function returns.
# $BREW_RECEIPT_AUDIT overrides the script path (the tests use it).

if [[ "${functions[brew]-}" != *_brew_receipt_audit_inner* ]]; then
    if (( ${+functions[brew]} )); then
        functions[_brew_receipt_audit_inner]=$functions[brew]
    else
        _brew_receipt_audit_inner() { command brew "$@"; }
    fi

    brew() {
        local brew_status=0
        _brew_receipt_audit_inner "$@" || brew_status=$?

        # Not after an interrupted upgrade (Ctrl-C and other signals exit >= 128).
        if [[ "$1" == upgrade ]] && (( brew_status < 128 && ! ${@[(Ie)--dry-run]} && ! ${@[(Ie)-n]} && ! ${@[(Ie)--cask]} )); then
            "${BREW_RECEIPT_AUDIT:-$HOME/mac-config/brew-tools/brew-receipt-audit.sh}" --quiet --log || true
        fi
        return $brew_status
    }
fi
