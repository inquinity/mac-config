# .zprofile is for login shells.
# It is basically the same as .zlogin except that it's sourced before .zshrc whereas .zlogin is sourced after .zshrc.
# According to the zsh documentation, ".zprofile is meant as an alternative to .zlogin for ksh fans; the two are not intended to be used together,
# although this could certainly be done if desired."

# After .zshenv 
# Before .zshrc .zlogin

ztrace "Loading ${(%):-%x}"

# /etc/zprofile ran /usr/libexec/path_helper immediately before this file, which
# rebuilds $PATH with /etc/paths + /etc/paths.d first and demotes everything
# .zshenv added to below /usr/bin. Re-assert the entries whose precedence
# actually matters, lowest priority first, since each --move lands at the front.
add_homebrew_paths
addpath --move /opt/homebrew/sbin
addpath --move /opt/homebrew/bin
addpath --move /opt/bin
addpath --move ~/mac-config/bin

#kubectl autocompletion
#autoload -Uz compinit
#compinit
#source <(kubectl completion zsh)

# legion homebrew info
export HOMEBREW_API_DOMAIN="https://mesh.s3api-core.optum.com/legion/homebrew"
export HOMEBREW_NO_AUTO_UPDATE="1"
export HOMEBREW_NO_VERIFY_ATTESTATIONS="1"
