#.zshrc
# Interactive shells

# History options
# Good source of info: https://zsh.sourceforge.io/Guide/zshguide02.html#l17
# HISTFILE set in /etc/zshrc
# HISTSIZE set in /etc/zshrc
# SAVEHISTset in /etc/zshrc

setopt APPEND_HISTORY

# This wil cause all session to share history (immediately) - it makes it difficult to work in multiple terminal windows and divide tasks
#setopt SHARE_HISTORY

# prevent duplicates when hitting the up arrow in the shell
#setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS

# set the prompt to be bash-like
PROMPT='%m %@ %# %/: '

#aliases
. ~/.aliases

#cd ~/dev
