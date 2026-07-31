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

(provide 'vastai)
;;; vastai.el ends here
