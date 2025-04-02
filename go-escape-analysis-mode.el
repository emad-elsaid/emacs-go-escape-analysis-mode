;;; go-escape-analysis.el --- Minor mode to display Go escape analysis annotations

;; Author: Emad Elsaid (Co-Authored by Claud)
;; Keywords: go, tools
;; Package-Requires: ((emacs "30.1"))

;;; Commentary:
;; This minor mode displays Go escape analysis information inline with your code.
;; It runs the Go compiler with escape analysis flags and adds the results as
;; annotations to the relevant lines in the buffer.

;;; Code:
(require 'compile)
(require 'cl-lib)

;;; will add annotations only for this list of issues
(setq go-escape-analysis-allowed '("leaking param"
                                   "escapes to heap"
                                   "moved to heap"))

(defgroup go-escape-analysis nil
  "Go escape analysis annotations."
  :group 'go)

(defcustom go-escape-analysis-detail-level 1
  "Level of detail for escape analysis (1 for normal, 2 for verbose)."
  :type 'integer
  :group 'go-escape-analysis)

(defface go-escape-analysis-annotation-face
  '((t :inherit font-lock-warning-face :slant italic))
  "Face used for escape analysis annotations."
  :group 'go-escape-analysis)

(defvar-local go-escape-analysis-overlays nil
  "Overlays used by go-escape-analysis-mode.")

(defun go-escape-analysis-clear-overlays ()
  "Clear all escape analysis overlays."
  (while go-escape-analysis-overlays
    (delete-overlay (pop go-escape-analysis-overlays))))

(defun go-escape-analysis--get-package-path ()
  "Get the Go package path for the current buffer."
  (let* ((file-name (buffer-file-name))
         (go-module (go-escape-analysis--find-go-module file-name))
         (rel-path (when go-module
                     (file-relative-name
                      (file-name-directory file-name)
                      (file-name-directory go-module)))))
    (if go-module
        (let ((module-name (go-escape-analysis--get-module-name go-module)))
          (if (string= rel-path "./")
              module-name
            (concat module-name "/" (directory-file-name rel-path))))
      (file-name-nondirectory (directory-file-name (file-name-directory file-name))))))

(defun go-escape-analysis--find-go-module (file-path)
  "Find go.mod file by traversing directories upward from FILE-PATH."
  (let ((dir (file-name-directory file-path)))
    (locate-dominating-file dir "go.mod")))

(defun go-escape-analysis--get-module-name (go-mod-dir)
  "Extract module name from go.mod file in GO-MOD-DIR."
  (let ((go-mod-file (expand-file-name "go.mod" go-mod-dir)))
    (when (file-exists-p go-mod-file)
      (with-temp-buffer
        (insert-file-contents go-mod-file)
        (goto-char (point-min))
        (when (re-search-forward "^module\\s-+\\(\"[^\"]+\"\\|[^\s\n]+\\)" nil t)
          (let ((module (match-string 1)))
            ;; Remove quotes if present
            (if (string-match "^\"\\(.*\\)\"$" module)
                (match-string 1 module)
              module)))))))

(defun go-escape-analysis--extract-analysis (package-path)
  "Run Go escape analysis for PACKAGE-PATH and return results."
  (let* ((detail-flag (if (> go-escape-analysis-detail-level 1) "-m -m" "-m"))
         (cmd (format "go build -gcflags=\"%s=%s\" ."
                      package-path detail-flag))
         (default-directory (file-name-directory (buffer-file-name)))
         (output (shell-command-to-string cmd))
         (file-name (file-name-nondirectory (buffer-file-name)))
         (results nil))

    ;; Process the output to extract relevant lines
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      (while (re-search-forward "\\(.+\\.go\\):\\([0-9]+\\):\\([0-9]+\\): \\(.*\\)$" nil t)
        (let ((found-file (match-string 1))
              (line-num (string-to-number (match-string 2)))
              (col-num (string-to-number (match-string 3)))
              (msg (string-trim (match-string 4))))
          ;; Only collect results for the current file
          (when (and (or (string= found-file (concat "./" file-name))
                         (string= found-file (buffer-file-name)))
                     (go-escape-analysis--is-allowed msg))
            (push (list line-num col-num msg) results))
          )))

    (nreverse results)))


(defun go-escape-analysis--annotate-buffer (analysis-results)
  "Add annotations to buffer based on ANALYSIS-RESULTS."
  (save-excursion
    (dolist (item analysis-results)
      (let ((line (nth 0 item))
            (col (nth 1 item))
            (msg (nth 2 item)))
        (goto-char (point-min))
        (forward-line (1- line))
        (let* ((line-end (line-end-position))
               (overlay (make-overlay line-end line-end)))
          (overlay-put overlay 'after-string
                       (propertize (format " 💡 %s" msg)
                                   'face 'go-escape-analysis-annotation-face))
          (push overlay go-escape-analysis-overlays))))))

(defun go-escape-analysis-run ()
  "Run escape analysis and annotate the current Go buffer."
  (interactive)
  (when (derived-mode-p 'go-mode)
    (go-escape-analysis-clear-overlays)
    (let ((package-path (go-escape-analysis--get-package-path)))
      (message "Analyzing Go package: %s" package-path)
      (let ((results (go-escape-analysis--extract-analysis package-path)))
        (if results
            (progn
              (go-escape-analysis--annotate-buffer results)
              (message "Found %d escape analysis annotations" (length results)))
          (message "No escape analysis annotations found"))))))

(defun go-escape-analysis--is-allowed (msg)
  "Check if MSG contains any substring from ALLOWED list."
  (cl-some (lambda (substr) (string-match-p (regexp-quote substr) msg)) go-escape-analysis-allowed))

;;;###autoload
(define-minor-mode go-escape-analysis-mode
  "Minor mode for displaying Go escape analysis annotations."
  :lighter " GoEsc"
  :group 'go-escape-analysis
  (if go-escape-analysis-mode
      (progn
        (go-escape-analysis-run)
        ;; Update annotations when saving
        (add-hook 'after-save-hook 'go-escape-analysis-run nil t))
    (go-escape-analysis-clear-overlays)
    (remove-hook 'after-save-hook 'go-escape-analysis-run t)))

(provide 'go-escape-analysis-mode)
;;; go-escape-analysis.el ends here
