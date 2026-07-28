# .zshenv is always sourced. It often contains exported variables that should be available to other programs.
# For example, $PATH, $EDITOR, and $PAGER are often set in .zshenv.
# Also, you can set $ZDOTDIR in .zshenv to specify an alternative location for the rest of your zsh configuration.

# Sourced first
# Before .zprofile .zshrc .zlogin

# Other path sources:
# /etc/paths
# /etc/paths.d

# Startup trace: touch ~/.zsh_trace to enable, rm ~/.zsh_trace to disable
[[ -f "${HOME}/.zsh_trace" ]] && ZSH_TRACE=1
source ~/mac-config/zsh/ztrace.sh

ztrace "Loading ${(%):-%x}"

source ~/mac-config/zsh/keychain_service_name.sh
source ~/mac-config/zsh/save_setting_in_keychain.sh
source ~/mac-config/zsh/load_setting_from_keychain.sh

# define addpath() here since this is the first sourced file
source ~/mac-config/zsh/addpath.sh

# Homebrew
# this is repeated in zprofile to ensure correct path ordering so brew folders come before /usr/*/bin
source ~/mac-config/zsh/add_homebrew_paths.sh
add_homebrew_paths

# Add Java paths (if Java exists)
# Note - homebrew java_home requires that you symlink the java folder to /Library/Java/JavaVirtualMachines:
# e.g: sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
if [[ -z "${JAVA_HOME:-}" ]]; then
    if JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null); then
	export JAVA_HOME
	addpath $JAVA_HOME/bin
    fi
fi

# Docker Desktop paths
if [ -d /Applications/Docker.app ]; then
    addpath ${HOME}/.docker/bin
    addpath /Applications/Docker.app/Contents/Resources/bin/
fi

# Rancher Desktop path
if [ -d ${HOME}/.rd ]; then addpath ${HOME}/.rd/bin ; fi

# Disable Microsoft CLI telemetry
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# Disable Save/Restore shell sessions
#export SHELL_SESSIONS_DISABLE=1

# Disable brew upgrade confirmation
export HOMEBREW_NO_ASK=1

# Load UHG specific settings (if file exists)
[[ -f ~/.zshenv-uhg ]] && source ~/.zshenv-uhg
