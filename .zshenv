# .zshenv is always sourced. It often contains exported variables that should be available to other programs.
# For example, $PATH, $EDITOR, and $PAGER are often set in .zshenv.
# Also, you can set $ZDOTDIR in .zshenv to specify an alternative location for the rest of your zsh configuration.

# Sourced first
# Before .zprofile .zshrc .zlogin

#echo Sourcing .zshenv

# define addpath() here since this is the first sourced file
addpath() {
    DIR=$1
    if [[ ":$PATH:" != *":$DIR:"* ]]; then
	export PATH="$DIR:$PATH"
    fi
}

if [[ $(uname -m) == 'arm64' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  addpath "/opt/bin"
  if [ -d /opt/homebrew/opt/mysql-client/bin ]; then
      addpath "/opt/homebrew/opt/mysql-client/bin"
  fi
fi

SHELL_SESSIONS_DISABLE=1

# Load UHG specific settings (if file exists)
. ~/.zshenv-uhg 2> /dev/null
