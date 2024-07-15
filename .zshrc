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

setopt INC_APPEND_HISTORY

# APPEND_HISTORY             # append the new history to the old, when shell exits
# INC_APPEND_HISTORY         # each line is added to the history when it is executed
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

# set the prompt to be bash-like
PROMPT='%m %@ %# %/: '

# Load UHG specific settings (if file exists)
#. ~/.zshrc-uhg 2> /dev/null

#aliases
. ~/.aliases



