# .zshenv is always sourced. It often contains exported variables that should be available to other programs.
# For example, $PATH, $EDITOR, and $PAGER are often set in .zshenv.
# Also, you can set $ZDOTDIR in .zshenv to specify an alternative location for the rest of your zsh configuration.

# Sourced first
# Before .zprofile .zshrc .zlogin

#echo Sourcing .zshenv

if [[ $(uname -m) == 'arm64' ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
  export PATH="/opt/bin:$PATH"
  if [ -d /opt/usrbin ]; then
    export PATH="/opt/usrbin:$PATH"
  fi
  if [ -d /opt/homebrew/opt/mysql-client/bin ]; then
    export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"
  fi
fi

SHELL_SESSIONS_DISABLE=1
