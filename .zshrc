# .zshrc is for interactive shells. You set options for the interactive shell there with the setopt and unsetopt commands.
# You can also load shell modules, set your history options, change your prompt, set up zle and completion, et cetera.
# You also set any variables that are only used in the interactive shell (e.g. $LS_COLORS).

# After .zshenv .zprofile
# Before .zlogin

#echo Sourcing .zshrc

# History options
# Good source of info: https://zsh.sourceforge.io/Guide/zshguide02.html#l17
# HISTFILE set in /etc/zshrc
# HISTSIZE set in /etc/zshrc
# SAVEHIST set in /etc/zshrc

setopt APPEND_HISTORY

# APPEND_HISTORY             # append the new history to the old, when shell exits
# INC_APPEND_HISTORY         # each line is added to the history when it is executed -- makes hgrep more difficult
# SHARE_HISTORY              # save history immediately, between shells -- makes it difficult to work in multiple terminal windows

# prevent duplicates when hitting the up arrow in the shell
# HIST_IGNORE_DUPS           # which tells the shell not to store a history line if it's the same as the previous one
# HIST_IGNORE_ALL_DUPS       # removes copies of lines still in the history list, keeping the newly added one
# HIST_EXPIRE_DUPS_FIRST     # it preferentially removes duplicates when the history fills up
# HIST_SAVE_NO_DUPS          # for the current session, the shell is not to save duplicated lines more than once
# HIST_FIND_NO_DUPS          # even if duplicate lines have been saved, searches backwards with editor commands don't show them more than once

setopt HIST_IGNORE_ALL_DUPS  # simply removes copies of lines still in the history list, keeping the newly added one

# history ignore commands
setopt HIST_IGNORE_SPACE     # do not save command beginning with a space
setopt HIST_NO_STORE         # tells the shell not to store history or fc commands
setopt HIST_NO_FUNCTIONS     # tells it not to store function definitions

# Load colors
#autoload -U colors && colors

# Enable prompt substitution (used for vcs_info)
setopt PROMPT_SUBST

# Enable vcs_info
# https://zsh.sourceforge.io/Doc/Release/User-Contributions.html#Version-Control-Information
autoload -Uz vcs_info

# We only need git and hg; all others will be disabled
zstyle ':vcs_info:*' enable git cvs
zstyle ':vcs_info:git:*' formats "%F{green}%b%f branch"

precmd() {
    # check for untracked files; unstaged changes; staged changes
    if [[ `git status --porcelain` ]] 2> /dev/null ; then

	# check for unstaged changes
	if ! git diff-files --quiet --ignore-submodules -- ; then
	    zstyle ':vcs_info:git:*' formats "%F{red}%b%f branch"
	else
	    # no unstaged changes; so check for staged changes
	    if ! git diff-index --cached --quiet HEAD --ignore-submodules -- ; then
		zstyle ':vcs_info:git:*' formats "%F{blue}%b%f branch"
	    else
		# if we have changes, but no unstaged or staged, it must be new files
		zstyle ':vcs_info:git:*' formats "%F{red}%b%f branch"
	    fi
	fi
    else
	zstyle ':vcs_info:git:*' formats "%F{green}%b%f branch"
    fi
    vcs_info
}

# set the prompt
PROMPT='%B%F{240}%~%f%b %F{red}%@ %#%f '
RPROMPT='${vcs_info_msg_0_}'

# Load UHG specific settings (if file exists)
#. ~/.zshrc-uhg 2> /dev/null

#aliases
. ~/.aliases

# Lines configured by zsh-newuser-install
#HISTFILE=~/.histfile
#HISTSIZE=1000
#SAVEHIST=1000

#setopt autocd
#bindkey -e
# End of lines configured by zsh-newuser-install

# The following lines were added by compinstall
zstyle :compinstall filename '/Users/raltman2/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall

# This will disable MicroTemplate Husky hooks
export HUSKY=0

# Added by gcloud cli
export CLOUDSDK_PYTHON=/usr/local/bin/python3
export PATH=$PATH:/Applications/google-cloud-sdk/bin
export REQUESTS_CA_BUNDLE=/Applications/google-cloud-sdk/Certs/standard_trusts.pem
