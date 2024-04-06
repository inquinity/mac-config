;; Add shortcut arrow keys for moving between windows
;; Shift-arrow moves in that direction
(when (fboundp 'windmove-default-keybindings)
  (windmove-default-keybindings))

;; Stop creating filename~ files
(setq make-backup-files nil)

;; Display line numbers
(global-display-line-numbers-mode 1)

;; Turn off display line wrapping
;; C-x x t to toggle this ad hoc
(setq-default truncate-lines 1)

;; Add undo/redo capability
;; https://www.emacswiki.org/emacs/UndoTree
(require 'undo-tree)
(global-undo-tree-mode)
(setq-default undo-tree-auto-save-history nil)

;; Hide the toolbar at the top of the window
;;(tool-bar-mode -1)

;; mac keyb mapping
;; default -- (setq mac-command-modifier 'meta)
;; default -- (setq mac-option-modifier (:function alt :mouse alt))

(setq mac-option-modifier 'meta)
(setq mac-command-modifier 'hyper)

;; Add Mac-friendly kbd
(keymap-global-set "H-z" 'undo-tree-undo)
(keymap-global-set "H-y" 'undo-tree-redo)
(keymap-global-set "C-/" nil)

;; macro shortcuts
(keymap-global-set "H-1" 'kmacro-start-macro)
(keymap-global-set "H-2" 'kmacro-end-macro)
(keymap-global-set "H-3" 'kmacro-end-and-call-macro)

;; Compare
(keymap-global-set "H-4" 'compare-windows)

;; Comments
;;(keymap-global-set "H-." 'uncomment-region)
;;(keymap-global-set "H-/" 'comment-region)
