#! zsh

# NOTE: do NOT copy .*-uhg
rsync --out-format="%f" --update ~/.zshenv .
rsync --out-format="%f" --update ~/.zprofile .
rsync --out-format="%f" --update ~/.zshrc .
rsync --out-format="%f" --update ~/.zlogin .
rsync --out-format="%f" --update ~/.zaliases .
rsync --out-format="%f" --update ~/.gitconfig .
rsync --out-format="%f" --update ~/.gitignore_global .
rsync --out-format="%f" --update ~/.emacs.d/init.el .emacs.d
rsync --delete --out-format="%f" --update --recursive ~/.emacs.d/el .emacs.d
rsync --delete --out-format="%f" --update --recursive ~/.emacs.d/elpa .emacs.d
