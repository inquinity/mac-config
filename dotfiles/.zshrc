# .zshrc is for interactive shells. You set options for the interactive shell there with the setopt and unsetopt commands.
# You can also load shell modules, set your history options, change your prompt, set up zle and completion, et cetera.
# You also set any variables that are only used in the interactive shell (e.g. $LS_COLORS).

# After .zshenv .zprofile
# Before .zlogin

ztrace "Loading ${(%):-%x}"

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

# Allow interactive comments so that copy/paste with comments will work (same as bash)
setopt interactivecomments

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

# True inside Claude Code's shell tool (CLAUDECODE) and the Claude desktop
# app's Terminal panel (TERM_PROGRAM), which don't need the fancy prompt/history.
_in_claude=0
[[ -n "$CLAUDECODE" || "$TERM_PROGRAM" == "claude-desktop" ]] && _in_claude=1

precmd() {
    # This only feeds the RPROMPT branch indicator, which is skipped inside
    # Claude shells (see below) -- don't spend git subprocess calls on every
    # prompt for a value that's never displayed there.
    (( _in_claude )) && return

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

# Disable atuin and extended git prompt
# - atuin's keybindings/rich UI don't play well inside embedded terminals
# - vscode has its own git integration
# - the git integration is just distracting inside Claude Code
if [[ "$TERM_PROGRAM" != "vscode" ]] && (( ! _in_claude )); then
    RPROMPT='${vcs_info_msg_0_}'

    # Added by atuin (shell history magic)
    eval "$(atuin init zsh)"
fi

# Separately: enable VS Code's own terminal shell integration (command
# decorations, exit-code markers, cwd detection). Unrelated to atuin above;
# only meaningful when actually running inside VS Code's integrated terminal.
if [[ "$TERM_PROGRAM" == "vscode" ]]; then
    source "$(code --locate-shell-integration-path zsh)"
fi

source ~/mac-config/zsh/source_first.sh
source ~/mac-config/zsh/alias_first.sh

# Load UHG specific settings (if file exists)
#. ~/.zshrc-uhg 2> /dev/null

# aliases
source_first ~/mac-config/zsh/alias.sh

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
# -C skips security check and reuses the dump file; run 'compinit' manually to rebuild
compinit -C
# End of lines added by compinstall

# Configure eza - see https://github.com/eza-community/eza-themes
export EZA_CONFIG_DIR=~/.config/eza

# set the key folder for age encryption utility
export AGE_KEY_DIR=~/.config/age

# Load UHG specific settings (if file exists)
[[ -f ~/.zshrc-uhg ]] && source ~/.zshrc-uhg
