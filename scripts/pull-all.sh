#!/bin/zsh
find . -type d -name ".git" -execdir zsh -c 'pwd; git pull' \;
