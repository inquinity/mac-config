# Suggestions from StackOverflow:
# 1. functions and aliasses should go in ~/.bashrc and ~/.bash_profile or ~/.profile should source ~/.bashrc
# 2. sourcing one from the other makes life much easier. For safety, I have my .bash_profile check first, like this: if [ -f ~/.bashrc ]; then . ~/.bashrc; fi

# imported from sample file
# From http://hayne.net/MacDev/Bash/aliases.bash

ztrace "Loading ${(%):-%x}"

#----------------------
# Startup trace control
#----------------------

alias zsh-trace-on='touch ~/.zsh_trace && echo "Startup trace: ON (takes effect on next shell)"'
alias zsh-trace-off='rm -f ~/.zsh_trace && echo "Startup trace: OFF (takes effect on next shell)"'
alias zsh-trace-status='[[ -f ~/.zsh_trace ]] && echo "Startup trace: ON" || echo "Startup trace: OFF"'

# -------------------
# Daily update script
# -------------------

alias update='~/mac-config/scripts/update.sh'

#-----------------
# Directory / list
#-----------------

if (($+commands[eza])) then
   alias la='eza --all $@'
   alias ll='eza --long --all --octal-permissions --icons=never $@'
   alias lt='eza --long --all --sort=time $@'
   # might need to use functions instead of alias due to bug that confuses completions (2025-August-25)
   #la () { eza --all $@ ; }
   #ll () { eza --long --all --octal-permissions --icons $@ ; }
   #lt () { eza --long --all --sort=time $@ ; }
else
   alias la='ls -aO'
   alias ll='ls -aOlh'
   alias lt='ls -lt'
fi

# list recrusive -- this requires quoted arquments
lr () { for pattern in "$@"; do find . -name "$pattern" -type f ; done ; }

# ls for resources MacOS fork
lsr () { ls -lh "$@"/..namedfork/rsrc ; }

#----------------
# Markdown viewer
#----------------

alias_first md treemd glow less

#--------
# Aliases
#--------

alias showpath='echo "$PATH" | tr ":" "\n" | nl'

# showa: to remind yourself of an alias (given some part of it)
alias showa='whence -f'

# sourcea: to source this file (to make changes active after editing)
alias sourcea='source ~/mac-config/zsh/alias.sh'

alias_first emacs '~/.emacs.d/open-with-emacs.sh'
# but what is /Applications/Emacs.app/Contents/MacOS/Emacs.sh

# GitHub Copilot REALLY likes timeout. This function does the same thing without needing to install GNU Coreutils 
function timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

#------
# Timer
#------

alias timer='command time -h'

#----------------
# Command history
#----------------

# Use atuin only if zshrc actually initialized it in this shell; it is
# skipped when not installed and inside VS Code / Claude Code terminals
if (( ${_atuin_active:-0} )); then
    alias h='atuin history list --cmd-only --session'
    alias hh='atuin history list  --cmd-only'
    alias hgrep='atuin search --cmd-only'
else
    alias h='history 1'
    alias hh='history 1 | less' # history (paged)
    alias hgrep='history 1 | grep -i'  # grep through command history
fi

#----------
# Searching
#----------

# ff:  to find a file under the current directory
ff () { find . -name "$@" ; }

# ffs: to find a file whose name starts with a given string
ffs () { find . -name "$@"'*' ; }

# ffe: to find a file whose name ends with a given string
ffe () { find . -name '*'"$@" ; }

# ----------------------
# AI Tools for shell CLI
# ----------------------

[[ -f ~/mac-config/scripts/x-command.sh ]] && source ~/mac-config/scripts/x-command.sh

# -----------
# Development
# -----------

# load custom node version selector (to set brew links for specific version)
source ~/mac-config/zsh/node-use.sh

alias python=python3
alias py=python3

# python-311() { alias python3 >/dev/null 2>&1 || if [[ $(uname -m) == 'arm64' ]]; then
#     alias python3=/opt/homebrew/bin/python3.11 ; export npm_config_python=/opt/homebrew/bin/python3.11
# else
#     alias python3=/usr/local/bin/python3.11 ; export npm_config_python=/usr/local/bin/python3.11
# fi; eval 'python3 --version' ; }

# python-312() { alias python3 >/dev/null 2>&1 && unalias python3 ; unset npm_config_python ; eval 'python3 --version' ; }

# ------------------------
# Mac OS & iOS Development
# ------------------------

# brew quarantine fix (removes quarantine attributes)
alias_first fix-brew-quarantine ~/mac-config/brew-tools/fix-brew-quarantine.sh

alias killdoc='killall -KILL Dock'

# Change Mac terminal name
term() { echo -n -e "\033]0;$@\007" ; }

# Objective-C / NIB searches
gr() { grep --line-number --recursive --include=*.{m,h,xib} "$1"; }
gri() { grep --line-number --recursive --ignore-case --include=*.{m,h,xib} "$1"; }

xcode ()  { open /Applications/Xcode.app "$@" ; }
sim () { open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app ; }

# -----------------
# Network / Hotspot
# -----------------

alias_first hotspot ~/mac-config/scripts/hotspot.sh

# --------------
# diff and merge
# --------------

alias_first visdiff /Applications/VisualDiffer.app/Contents/Helpers/visdiff
alias_first vdiff opendiff

if command -v "/Applications/kdiff3.app" &>/dev/null; then
   kdiff3() { open "/Applications/kdiff3.app" "$@" ; }
   # kdiff two files
   kd ()  { open -a kdiff3 --args "$PWD/$1" "$PWD/$2"; }
   # kdiff merge two files to using a .merged output file
   km () { open -a kdiff3 --args "$PWD/$1" "$PWD/$2" --output "$(PWD)/$1.merged"; }
   # kdiff merge two files in place (overwrites first file)
   kdm () { open -a kdiff3 --args "$PWD/$1" "$PWD/$2" --output "$(PWD)/$1"; }
fi

# -------------
# Convert Video
# -------------

source ~/mac_config/zsh/convert-video.sh

# ----------
# Encryption
# ----------

# Source Encryption functions from external library
source_first ~/mac-config/scripts/encryption.sh

# -----------------
# Container Runtime
# -----------------

# Source docker functions from external library
source_first ~/mac-config/scripts/docker.sh

# -----------------------------------------------------------------
# --- use switchable container runtimes (docker, nerdctl, etc.) ---
# Source nerdctl (Rancher Desktop) functions from external library
# source_first ~/mac-config/scripts/nerdctl.sh

# Source docker daemon-specific functions from external library
# source_first ~/mac-config/scripts/dockerdaemon.sh

# If you want switched-docker methods/aliases then source the following file
# source_first ~/mac-config/scripts/docker-utils-switched.sh
# --- use switchable container runtimes (docker, nerdctl, etc.) ---
# -----------------------------------------------------------------

alias_first grype ~/mac-config/scripts/grype.sh
alias_first get-main-package ~/mac-config/scripts/get-main-package.sh

# compatibility work-around for dive and containerd
# alias_first dive ~/mac-config/scripts/dive.sh

alias_first container-extract ~/dev/team/docker/scripts/container-extract.sh ~/mac-config/scripts/container-extract.sh

alias_first grype ~/mac-config/scripts/grype.sh
alias_first image-extract ~/dev/team/docker/scripts/image-extract.sh ~/mac-config/scripts/image-extract.sh

# SBOM comparison
alias_first sbom-diff ~/dev/team/docker/sbom-compare/sbom-diff.sh ~/mac-config/sbom-compare/sbom-diff.sh
alias_first sbom-analyze ~/dev/team/docker/sbom-compare/sbom-analyze.sh ~/mac-config/sbom-compare/sbom-analyze.sh

# ---------
# Optum/UHG
# ---------

# microproduct template cli
alias mpt='npx @optum-rx-platform/cli@latest'

# docker scripts
alias_first prisma ~/dev/team/docker/prismsa/prisma.sh
alias_first xray ~/dev/team/docker/scripts/xray.sh

# Source APK functions from external library
source_first ~/dev/GoldenImageCoP/cookbook/apk-search/apk-functions.sh

# Source hcc-auth
alias_first hcc-auth ~/dev/team/scripts/hcc-auth.sh

# codeql
alias_first codeql ~/mac-config/scripts/codeql.sh

# gcitool
alias_first gci ~/dev/optum/gcitool/scripts/gcictl.sh

# backup
alias_first backup ~/Local/mac-backup/backup.command

# bookmarks
alias_first sync-edge ~/Local/sync-edge-bookmarks.command
