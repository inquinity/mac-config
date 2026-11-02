;;; early-init.el --- Loaded before package and UI initialization -*- lexical-binding: t -*-

;; The libgccjit bundled with Emacs.app derives the macOS deployment target
;; from the Darwin kernel version (major - 9).  That broke when Apple
;; renumbered to macOS 26: Darwin 27 yields "18.0", which clang rejects, so
;; every native compile fails.  Passing the real version explicitly stops
;; the driver from guessing.
(when (and (eq system-type 'darwin) (featurep 'native-compile))
  (setq native-comp-driver-options
        (list (concat "-mmacosx-version-min="
                      (string-trim
                       (shell-command-to-string "sw_vers -productVersion"))))))

;; Resize frames by pixel rather than by character cell.  Testing whether
;; this fixes the stalled, janky live-resize drag on macOS 27.2 (see
;; jdtsmith/emacs-mac PR #157).  Set here so the first frame has it.
(setq frame-resize-pixelwise t)

;;; early-init.el ends here
