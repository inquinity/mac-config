# .zprofile is for login shells.
# It is basically the same as .zlogin except that it's sourced before .zshrc whereas .zlogin is sourced after .zshrc.
# According to the zsh documentation, ".zprofile is meant as an alternative to .zlogin for ksh fans; the two are not intended to be used together,
# although this could certainly be done if desired."

# After .zshenv 
# Before .zshrc .zlogin

#echo Sourcing .zprofile

# This is the easiest way to "fix" the path ordering issue and make sure that homebrew is search before /usr/*/bin
if [[ $(uname -m) == 'arm64' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  addpath "/opt/bin"
  if [ -d /opt/homebrew/opt/mysql-client/bin ]; then
      addpath "/opt/homebrew/opt/mysql-client/bin"
  fi
fi

#kubectl autocompletion
#autoload -Uz compinit
#compinit
#source <(kubectl completion zsh)
