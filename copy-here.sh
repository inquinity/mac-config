#! zsh
diff ~/.aliases .aliases
diff ~/.emacs.d/init.el .emacs.d
diff ~/.gitconfig .gitconfig
diff ~/.gitignore_global .gitignore_global
diff ~/.zprofile .zprofile
diff ~/.zshenv .zshenv
diff ~/.zshrc .zshrc
read -s -k '?Press any key to continue.'
cp ~/.aliases .
cp ~/.emacs.d/init.el .emacs.d
cp ~/.gitconfig .
cp ~/.gitignore_global .
cp ~/.zprofile .
cp ~/.zshenv .
cp ~/.zshrc .
