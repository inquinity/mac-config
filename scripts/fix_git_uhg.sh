#!/bin/zsh
#not needed
#find . -type d -name ".git" -execdir zsh -c 'pwd; git remote set-url origin $(git remote get-url origin | sed "s|https://github|https://raltman2_uhg@github|g")' \;

