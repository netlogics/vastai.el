;;; vastai.el --- Emacs interface for the Vast.ai GPU cloud API -*- lexical-binding: t; -*-

;; Author: Phil
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (transient "0.4.0"))
;; Keywords: tools, cloud, gpu

;;; Commentary:
;; Transient-driven interface to the Vast.ai REST API.
;; Manage GPU instances, search offers, browse templates, view costs.

;;; Code:

(require 'json)
(require 'url)
(require 'transient)

(defconst vastai--base-url "https://console.vast.ai"
  "Base URL for the Vast.ai API.")

(defgroup vastai nil
  "Emacs interface for the Vast.ai GPU cloud API."
  :prefix "vastai-"
  :group 'tools)

(defcustom vastai-api-key nil
  "Vast.ai API key. If nil, falls back to `vastai-api-key-file'."
  :type '(choice (const nil) string)
  :group 'vastai)

(defcustom vastai-api-key-file
  (expand-file-name "~/.config/vastai/vast_api_key")
  "Path to file containing the Vast.ai API key."
  :type 'file
  :group 'vastai)

(defun vastai--api-key ()
  "Return the Vast.ai API key or signal `user-error' if unavailable."
  (or vastai-api-key
      (when (file-readable-p vastai-api-key-file)
        (string-trim (with-temp-buffer
                       (insert-file-contents vastai-api-key-file)
                       (buffer-string))))
      (user-error
       "vastai: set vastai-api-key or run: vastai set api-key <KEY>")))

(defun vastai--build-url (endpoint &optional params)
  "Build full API URL for ENDPOINT with optional query PARAMS alist."
  (let ((url (concat vastai--base-url endpoint)))
    (if params
        (concat url "?" (url-build-query-string params))
      url)))

(defun vastai--parse-json-response (buf)
  "Parse JSON body from HTTP response buffer BUF. Return alist or nil."
  (with-current-buffer buf
    (goto-char (point-min))
    (when (re-search-forward "\r?\n\r?\n" nil t)
      (condition-case err
          (json-read)
        (error (message "vastai: JSON parse error: %s" err) nil)))))

(defun vastai--request (method endpoint &optional params body)
  "Make a METHOD request to ENDPOINT with query PARAMS and JSON BODY.
Returns parsed alist or nil on error."
  (let* ((url-request-method method)
         (url-request-extra-headers
          `(("Authorization" . ,(concat "Bearer " (vastai--api-key)))
            ("Content-Type" . "application/json")))
         (url-request-data
          (when body
            (encode-coding-string (json-encode body) 'utf-8)))
         (url (vastai--build-url endpoint params))
         (buf (condition-case err
                  (url-retrieve-synchronously url t t 30)
                (error (message "vastai: HTTP error: %s" err) nil))))
    (when buf
      (prog1 (vastai--parse-json-response buf)
        (kill-buffer buf)))))

(defun vastai--format-alist (alist)
  "Format ALIST as aligned key: value lines."
  (mapconcat (lambda (pair)
               (format "%-24s %s" (car pair) (cdr pair)))
             alist "\n"))

(defun vastai--display (title content)
  "Display CONTENT under TITLE in the *vastai* read-only buffer."
  (let ((buf (get-buffer-create "*vastai*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert title "\n" (make-string (length title) ?─) "\n\n")
        (insert content "\n"))
      (special-mode)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(provide 'vastai)
;;; vastai.el ends here
