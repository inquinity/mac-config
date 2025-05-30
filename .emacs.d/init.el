;; Auto-reload changed files
(global-auto-revert-mode 1)

;; Add shortcut arrow keys for moving between windows
;; Shift-arrow moves in that direction
(when (fboundp 'windmove-default-keybindings) (windmove-default-keybindings))

;; Stop creating filename~ files
(setq make-backup-files nil)

;; Stop creating #file# backups
(setq auto-save-default nil)

;; Turn off .#files
(setq create-lockfiles nil)

;; Display line numbers
(global-display-line-numbers-mode 1)

;; show cursor position within line
(column-number-mode 1)

;; Turn off display line wrapping
;; C-x x t to toggle this ad hoc
(setq-default truncate-lines 1)

;; Add undo/redo capability
;; https://www.emacswiki.org/emacs/UndoTree
(require 'undo-tree)
(global-undo-tree-mode)
(setq-default undo-tree-auto-save-history nil)

;; Bookmarks
(add-to-list 'load-path "~/.emacs.d/el/bm/")
(require 'bm)
(keymap-global-set "H-b" 'bm-toggle)
(keymap-global-set "H-n" 'bm-next)
(keymap-global-set "H-p" 'bm-previous)

;; Hide the toolbar at the top of the window
;;(tool-bar-mode -1)

;; Adjust JSON indent level
(setq js-indent-level 2)

;; Markdown mode
;; https://jblevins.org/projects/markdown-mode/
(require 'package)
(add-to-list 'package-archives '("melpa-stable" . "https://stable.melpa.org/packages/"))
(package-initialize)
;; then: M-x package-install RET markdown-mode RET

;; mac keyb mapping
;; default -- (setq mac-command-modifier 'meta)
;; default -- (setq mac-option-modifier (:function alt :mouse alt))

(setq mac-option-modifier 'meta)
(setq mac-command-modifier 'hyper)

;; Add Mac-friendly keyboard mappings
(keymap-global-set "H-z" 'undo-tree-undo)
(keymap-global-set "H-y" 'undo-tree-redo)
(keymap-global-set "C-/" nil)

;; macro shortcuts
(keymap-global-set "H-1" 'kmacro-start-macro)
(keymap-global-set "H-2" 'kmacro-end-macro)
(keymap-global-set "H-3" 'kmacro-end-and-call-macro)

;; Compare
(keymap-global-set "H-4" 'compare-windows)

;; Window-sizing commands
(keymap-global-set "H-[" 'shrink-window-horizontally)
(keymap-global-set "H-]" 'enlarge-window-horizontally)

;; sort-buffer
(defun sort-buffer ()
  "Select all text in the buffer and sort it."
  (interactive)
  (save-excursion
    (mark-whole-buffer)
    (sort-lines nil (point-min) (point-max))))

(keymap-global-set "H-5" 'sort-buffer)

(defun sort-region ()
  "Sort all lines in the selected region."
  (interactive)
  (if (use-region-p)
      (let ((start (region-beginning))
            (end (region-end)))
        (goto-char start)
        (beginning-of-line)
        (set-mark (point))
        (goto-char end)
        (end-of-line)
        (sort-lines nil (region-beginning) (region-end)))
    (message "No region selected")))

(keymap-global-set "H-6" 'sort-region)

;; Comments - Not working the way it should
;;(keymap-global-set "H-." 'uncomment-region)
;;(keymap-global-set "H-/" 'comment-region)

;; using ls-lisp with these settings gives case-insensitive sorting on MacOS
(require 'ls-lisp)
(setq dired-listing-switches "-alhG")
(setq ls-lisp-use-insert-directory-program nil)
(setq ls-lisp-ignore-case t)
(setq ls-lisp-use-string-collate nil)
;; customise the appearance of the listing
(setq ls-lisp-verbosity '(links uid))
(setq ls-lisp-format-time-list '("%b %e %H:%M" "%b %e  %Y"))
(setq ls-lisp-use-localized-time-format t)
