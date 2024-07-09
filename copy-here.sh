#! zsh
#diff ~/.aliases .aliases
#diff ~/.emacs.d/init.el .emacs.d
#diff ~/.gitconfig .gitconfig
#diff ~/.gitignore_global .gitignore_global
#diff ~/.zprofile .zprofile
#diff ~/.zshenv .zshenv
#diff ~/.zshrc .zshrc
#read -s -k '?Press enter to continue.'
cp -v ~/.zshenv .
cp -v ~/.zprofile .
cp -v ~/.zshrc .
cp -v ~/.zlogin .
cp -v ~/.aliases .
# do NOT copy .uhg-zshrc
cp -v ~/.emacs.d/init.el .emacs.d
cp -v -R ~/.emacs.d/el .emacs.d
cp -v -R ~/.emacs.d/elpa .emacs.d
cp -v ~/.gitconfig .
cp -v ~/.gitignore_global .
#cp -v -R /opt/usrbin/* ./opt/usrbin
