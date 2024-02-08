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

;; mac keyb mapping
;; default -- (setq mac-command-modifier 'meta)
;; default -- (setq mac-option-modifier (:function alt :mouse alt))

(setq mac-option-modifier 'meta)
(setq mac-command-modifier 'hyper)

