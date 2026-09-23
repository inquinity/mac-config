;;; init.el --- Personal configuration -*- lexical-binding: t -*-

;;;; Housekeeping

;; Keep Customize output out of this file.
(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file 'noerror 'nomessage)

;; No filename~ backups, #file# auto-saves, or .#file lock files.
(setq make-backup-files nil
      auto-save-default nil
      create-lockfiles nil)

;;;; Packages

(require 'package)
(add-to-list 'package-archives
             '("melpa-stable" . "https://stable.melpa.org/packages/") t)
;; Prefer GNU/NonGNU ELPA; fall back to MELPA Stable for anything else.
(setq package-archive-priorities '(("gnu" . 10) ("nongnu" . 5) ("melpa-stable" . 0)))

;;;; Editing and display

(global-auto-revert-mode 1)
(global-display-line-numbers-mode 1)
(column-number-mode 1)

;; No line wrapping; C-x x t toggles it ad hoc.
(setq-default truncate-lines t)

(setq js-indent-level 2)

;; Shift-<arrow> moves between windows.
(windmove-default-keybindings)

;;;; macOS keyboard

;; Left Cmd stays Cmd (super, so Cmd-C/V/Q etc. behave as in other Mac
;; apps).  Right Cmd is Hyper, a modifier nothing else binds, reserved for
;; personal bindings.  Option is Meta, Control is Control.
(setq ns-command-modifier 'super
      ns-right-command-modifier 'hyper
      ns-option-modifier 'meta
      ns-control-modifier 'control)

;; Undo is Cmd-Z by default; redo on Cmd-Shift-Z and Cmd-Y (replacing the
;; rarely used ns-paste-secondary).
(keymap-global-set "s-Z" #'undo-redo)
(keymap-global-set "s-y" #'undo-redo)
(keymap-global-unset "C-/")

;; Keyboard macros
(keymap-global-set "H-1" #'kmacro-start-macro)
(keymap-global-set "H-2" #'kmacro-end-macro)
(keymap-global-set "H-3" #'kmacro-end-and-call-macro)

(keymap-global-set "H-4" #'compare-windows)

;; Window sizing
(keymap-global-set "H-[" #'shrink-window-horizontally)
(keymap-global-set "H-]" #'enlarge-window-horizontally)

;; Use C-<backspace> for backward-kill-word instead.
(keymap-global-unset "M-<delete>")
(keymap-global-unset "M-DEL")

;;;; Sorting

(defun sort-buffer ()
  "Sort all lines in the buffer."
  (interactive)
  (sort-lines nil (point-min) (point-max)))

(defun sort-region ()
  "Sort the lines touched by the active region, extended to whole lines."
  (interactive)
  (if (use-region-p)
      (let ((start (save-excursion (goto-char (region-beginning)) (line-beginning-position)))
            (end (save-excursion (goto-char (region-end)) (line-end-position))))
        (sort-lines nil start end))
    (message "No region selected")))

(keymap-global-set "H-5" #'sort-buffer)
(keymap-global-set "H-6" #'sort-region)

;;;; Third-party packages

;; Visible, toggleable line bookmarks.
(use-package bm
  :ensure t
  :bind (("H-b" . bm-toggle)
         ("H-n" . bm-next)
         ("H-p" . bm-previous)))

;; Autoloads register .md/.markdown, so nothing loads until one is opened.
(use-package markdown-mode
  :ensure t
  :defer t)

;;;; Dired

;; ls-lisp gives case-insensitive sorting on macOS (BSD ls cannot).
(use-package ls-lisp
  :custom
  (ls-lisp-use-insert-directory-program nil)
  (ls-lisp-ignore-case t)
  (ls-lisp-use-string-collate nil)
  (ls-lisp-verbosity '(links uid))
  (ls-lisp-format-time-list '("%b %e %H:%M" "%b %e  %Y"))
  (ls-lisp-use-localized-time-format t))

(setq dired-listing-switches "-alhG")

;;;; Server for emacsclient

(require 'server)
(unless (server-running-p)
  (server-start))

;;; init.el ends here
