;;; vastai.el --- Emacs interface for the Vast.ai GPU cloud API -*- lexical-binding: t; -*-

;; Author: Phil
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1"))
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

(defcustom vastai-offer-type "on-demand"
  "Type of GPU offers that `vastai-search-offers' queries.

The value maps directly to the Vast.ai API `type' filter:

- \"on-demand\"  fixed-price offers (the default),
- \"bid\"        interruptible (spot) offers, cheaper but preemptible,
- \"reserved\"   reserved-capacity offers.

Toggle the common on-demand/interruptible choice interactively with
`vastai-toggle-offer-type'."
  :type '(choice (const :tag "On-demand" "on-demand")
                 (const :tag "Interruptible (bid)" "bid")
                 (const :tag "Reserved" "reserved"))
  :group 'vastai)

(defun vastai--api-key ()
  "Return the Vast.ai API key or signal `user-error' if unavailable."
  (or vastai-api-key
      (when (file-readable-p vastai-api-key-file)
        (let ((key (string-trim (with-temp-buffer
                                  (insert-file-contents vastai-api-key-file)
                                  (buffer-string)))))
          (unless (string-empty-p key) key)))
      (user-error
       "vastai: set vastai-api-key or run: vastai set api-key <KEY>")))

(defun vastai--build-url (endpoint &optional params)
  "Build full API URL for ENDPOINT with optional query PARAMS alist."
  (let ((url (concat vastai--base-url endpoint)))
    (if params
        (concat url "?" (url-build-query-string params))
      url)))

(defun vastai--parse-json-response (buf)
  "Parse JSON body from HTTP response buffer BUF. Return alist or nil on error.

On a non-2xx status, return nil and surface the server's error message
when one is present, so authentication or parameter problems become
visible instead of silently yielding an empty result."
  (with-current-buffer buf
    (goto-char (point-min))
    (if (not (re-search-forward "^HTTP/[0-9.]+ \\([0-9]+\\)" nil t))
        (progn (message "vastai: could not parse HTTP status") nil)
      (let* ((status (string-to-number (match-string 1)))
             (has-body (re-search-forward "\r?\n\r?\n" nil t))
             (body (when has-body
                     (condition-case err
                         (json-read)
                       (error (message "vastai: JSON parse error: %s" err)
                              nil)))))
        (if (not (and (>= status 200) (< status 300)))
            (progn
              (message "vastai: HTTP %d%s" status
                       (if (listp body)
                           (let ((detail (or (alist-get 'msg body)
                                             (alist-get 'error body))))
                             (if detail (concat ": " (format "%s" detail)) ""))
                         ""))
              nil)
          body)))))

(defun vastai--request (method endpoint &optional params body)
  "Make a METHOD request to ENDPOINT with query PARAMS and JSON BODY.
Returns parsed alist or nil on error."
  (let* ((url-request-method method)
         (url-request-extra-headers
          (append `(("Authorization" . ,(concat "Bearer " (vastai--api-key))))
                  (when body '(("Content-Type" . "application/json")))))
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
               (format "%-23s: %s" (car pair) (cdr pair)))
             alist "\n"))

(defvar vastai-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "l") #'vastai-list-instances)
    (define-key map (kbd "s") #'vastai-search-offers)
    (define-key map (kbd "t") #'vastai-list-templates)
    (define-key map (kbd "c") #'vastai-show-costs)
    (define-key map (kbd "T") #'vastai-toggle-offer-type)
    (define-key map (kbd "?") #'vastai)
    map)
  "Keymap for `vastai-mode'.")

(define-derived-mode vastai-mode special-mode "Vast.ai"
  "Major mode for Vast.ai output buffers.
\\{vastai-mode-map}")

(defun vastai--display (title content)
  "Display CONTENT under TITLE in the *vastai* read-only buffer."
  (let ((buf (get-buffer-create "*vastai*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert title "\n" (make-string (length title) ?─) "\n\n")
        (insert content "\n\n")
        (insert (propertize
                 "Keys: l=instances  s=search  t=templates  c=costs  T=toggle type  ?=menu  q=quit"
                 'face 'shadow)))
      (unless (eq major-mode 'vastai-mode) (vastai-mode))
      (goto-char (point-min)))
    (display-buffer buf '(display-buffer-same-window))
    (when-let ((win (get-buffer-window buf)))
      (fit-window-to-buffer win nil 10))))

(defun vastai--fetch-instances ()
  "Fetch list of instances from the API. Returns vector of alists."
  (let ((result (vastai--request "GET" "/api/v1/instances/")))
    (when result
      (or (alist-get 'instances result) []))))

(defun vastai--format-instance (instance)
  "Format INSTANCE alist as a completing-read candidate string."
  (format "%s | %s | %dx %s | $%.4f/hr | %s"
          (alist-get 'id instance "")
          (alist-get 'actual_status instance "unknown")
          (alist-get 'num_gpus instance 0)
          (alist-get 'gpu_name instance "")
          (alist-get 'dph_total instance 0.0)
          (or (alist-get 'label instance) "")))

(defun vastai--instance-id-from-candidate (candidate)
  "Extract instance ID string from a formatted CANDIDATE."
  (car (split-string candidate " | " t)))

(defun vastai--instance-details (instance)
  "Format INSTANCE alist as a human-readable detail string."
  (vastai--format-alist
   (seq-filter (lambda (pair) (not (null (cdr pair))))
               (list (cons "ID"       (alist-get 'id instance))
                     (cons "Status"   (alist-get 'actual_status instance))
                     (cons "GPU"      (format "%dx %s"
                                              (alist-get 'num_gpus instance 0)
                                              (alist-get 'gpu_name instance "")))
                     (cons "Price"    (format "$%.4f/hr"
                                              (alist-get 'dph_total instance 0.0)))
                     (cons "Label"    (alist-get 'label instance))
                     (cons "Image"    (alist-get 'image_uuid instance))
                     (cons "Disk"     (when (alist-get 'disk_space instance)
                                        (format "%s GB"
                                                (alist-get 'disk_space instance))))
                     (cons "SSH Host" (alist-get 'ssh_host instance))
                     (cons "SSH Port" (alist-get 'ssh_port instance))))))

(defun vastai--cmd-stop ()
  "Stop the instance stored in the current transient's scope."
  (interactive)
  (let ((id (oref transient--prefix scope)))
    (when (y-or-n-p (format "Stop instance %s? " id))
      (vastai--request "PUT" (format "/api/v0/instances/%s/" id)
                       nil '((state . "stopped")))
      (message "vastai: stop requested for instance %s" id))))

(defun vastai--cmd-start ()
  "Start the instance stored in the current transient's scope."
  (interactive)
  (let ((id (oref transient--prefix scope)))
    (when (y-or-n-p (format "Start instance %s? " id))
      (vastai--request "PUT" (format "/api/v0/instances/%s/" id)
                       nil '((state . "running")))
      (message "vastai: start requested for instance %s" id))))

(defun vastai--cmd-delete ()
  "Permanently delete the instance stored in the current transient's scope."
  (interactive)
  (let ((id (oref transient--prefix scope)))
    (when (y-or-n-p (format "PERMANENTLY DELETE instance %s? " id))
      (vastai--request "DELETE" (format "/api/v0/instances/%s/" id))
      (message "vastai: deleted instance %s" id))))

(defun vastai--cmd-show ()
  "Show details of the instance stored in the current transient's scope."
  (interactive)
  (let* ((id (oref transient--prefix scope))
         (instances (vastai--fetch-instances))
         (instance (seq-find (lambda (i)
                               (equal (format "%s" (alist-get 'id i)) id))
                             instances)))
    (if instance
        (vastai--display (format "Instance %s" id)
                         (vastai--instance-details instance))
      (message "vastai: instance %s not found" id))))

(transient-define-prefix vastai--instance-action (id)
  "Actions for a Vast.ai instance. ID is stored as scope."
  [:description (lambda () (format "Instance %s" (oref transient--prefix scope)))
   ("s" "Stop"         vastai--cmd-stop)
   ("S" "Start"        vastai--cmd-start)
   ("d" "Delete"       vastai--cmd-delete)
   ("i" "Show details" vastai--cmd-show)]
  (interactive "s")
  (transient-setup 'vastai--instance-action nil nil id))

(defun vastai-list-instances ()
  "List Vast.ai instances via completing-read, then show action transient."
  (interactive)
  (let* ((instances (vastai--fetch-instances))
         (candidates (mapcar #'vastai--format-instance instances)))
    (if (seq-empty-p candidates)
        (message "vastai: no instances found")
      (let* ((choice (completing-read "Instance: " candidates nil t))
             (id (vastai--instance-id-from-candidate choice)))
        (vastai--instance-action id)))))

(defun vastai--parse-filters (filter-string)
  "Parse FILTER-STRING like \"gpu_name=RTX_4090 num_gpus=1\" into alist.
Each token must be KEY=VALUE. Unquoted values have underscores replaced with
spaces (e.g. RTX_4090 -> \"RTX 4090\"). Quote values to preserve underscores:
image_uuid=\"some_id_v1\" keeps underscores."
  (when (and filter-string (not (string-empty-p filter-string)))
    (mapcar (lambda (token)
              (if (string-match "\\([^=]+\\)=\\(.+\\)" token)
                  (let* ((key (match-string 1 token))
                         (raw (match-string 2 token))
                         (val (if (string-match "\\`[\"']\\(.*\\)[\"']\\'" raw)
                                  (match-string 1 raw)
                                (replace-regexp-in-string "_" " " raw))))
                    (cons key `((eq . ,val))))
                (user-error "vastai: invalid filter token: %s" token)))
            (split-string filter-string " " t))))

(defun vastai--build-search-body (user-filters &optional offer-type)
  "Build the complete JSON body alist for a bundle search request.
USER-FILTERS is an alist from `vastai--parse-filters'.  OFFER-TYPE is
the API `type' filter and defaults to `vastai-offer-type'."
  (append `((verified . ((eq . t)))
            (external . ((eq . :json-false)))
            (rentable . ((eq . t)))
            (type . ,(or offer-type vastai-offer-type))
            (allocated_storage . 5.0)
            (order . [["score" "desc"]]))
          user-filters))

(defun vastai--fetch-offers (filter-string)
  "Fetch offers matching FILTER-STRING. Returns vector of alists."
  (let* ((user-filters (vastai--parse-filters filter-string))
         (body (vastai--build-search-body user-filters))
         (result (vastai--request "POST" "/api/v0/bundles/" nil body)))
    (when result
      (or (alist-get 'offers result) []))))

(defun vastai--format-offer (offer)
  "Format OFFER alist as a completing-read candidate string."
  (format "%s | %dx %s | $%.4f/hr | %s"
          (alist-get 'id offer "")
          (alist-get 'num_gpus offer 0)
          (alist-get 'gpu_name offer "")
          (alist-get 'dph_total offer 0.0)
          (alist-get 'geolocation offer "")))

(defun vastai--offer-id-from-candidate (candidate)
  "Extract offer ID string from a formatted CANDIDATE."
  (car (split-string candidate " | " t)))

(defun vastai--offer-details (offer)
  "Format OFFER alist as a human-readable detail string."
  (vastai--format-alist
   (seq-filter (lambda (pair) (not (null (cdr pair))))
               (list (cons "Offer ID"    (alist-get 'id offer))
                     (cons "GPU"         (format "%dx %s"
                                                  (alist-get 'num_gpus offer 0)
                                                  (alist-get 'gpu_name offer "")))
                     (cons "GPU RAM"     (when (alist-get 'gpu_ram offer)
                                           (format "%s GB" (alist-get 'gpu_ram offer))))
                     (cons "Price"       (format "$%.4f/hr"
                                                  (alist-get 'dph_total offer 0.0)))
                     (cons "Location"    (alist-get 'geolocation offer))
                     (cons "Reliability" (alist-get 'reliability2 offer))
                     (cons "Upload"      (when (alist-get 'inet_up offer)
                                           (format "%s Mbps" (alist-get 'inet_up offer))))
                     (cons "Download"    (when (alist-get 'inet_down offer)
                                           (format "%s Mbps"
                                                   (alist-get 'inet_down offer))))))))

(defvar vastai--current-offer nil
  "Most recently selected offer alist; used by offer action commands.")

(defun vastai--cmd-provision ()
  "Provision (rent) the offer stored in the current transient's scope."
  (interactive)
  (let* ((id (oref transient--prefix scope))
         (image (read-string "Docker image: " "pytorch/pytorch:latest"))
         (disk (string-to-number (read-string "Disk GB: " "20")))
         (label (read-string "Label (optional): ")))
    (when (y-or-n-p (format "Provision offer %s with %s, %d GB disk? " id image disk))
      (let ((result (vastai--request
                     "PUT" (format "/api/v0/asks/%s/" id)
                     nil
                     `((client_id . "me")
                       (image . ,image)
                       (disk . ,disk)
                       (label . ,label)
                       (onstart . "")
                       (runtype . "args")
                       (use_ssh . t)
                       (ssh_direct . :json-false)
                       (use_jupyter_lab . :json-false)))))
        (if result
            (message "vastai: instance created from offer %s" id)
          (message "vastai: failed to provision offer %s" id))))))

(defun vastai--cmd-offer-show ()
  "Show details of the offer stored in the current transient's scope."
  (interactive)
  (let ((id (oref transient--prefix scope)))
    (if vastai--current-offer
        (vastai--display (format "Offer %s" id)
                         (vastai--offer-details vastai--current-offer))
      (message "vastai: no offer details cached"))))

(transient-define-prefix vastai--offer-action (id)
  "Actions for a Vast.ai offer. ID is stored as scope."
  [:description (lambda () (format "Offer %s" (oref transient--prefix scope)))
   ("p" "Provision (rent)" vastai--cmd-provision)
   ("i" "Show details"     vastai--cmd-offer-show)]
  (interactive "s")
  (transient-setup 'vastai--offer-action nil nil id))

(defun vastai-toggle-offer-type ()
  "Toggle `vastai-offer-type' between on-demand and interruptible offers.

On-demand offers are fixed-price; interruptible (bid) offers are
cheaper but can be preempted by other users."
  (interactive)
  (setq vastai-offer-type
        (if (equal vastai-offer-type "bid") "on-demand" "bid"))
  (message "vastai: offer type is now %s"
           (if (equal vastai-offer-type "bid")
               "interruptible (bid)" "on-demand")))

(defun vastai-search-offers ()
  "Search Vast.ai GPU offers via completing-read, then show action transient."
  (interactive)
  (let* ((filter-str (read-string
                      (format "Filter (%s offers, e.g. gpu_name=RTX_4090 num_gpus=1): "
                              vastai-offer-type)))
         (offers (vastai--fetch-offers filter-str))
         (candidates (mapcar #'vastai--format-offer offers)))
    (if (seq-empty-p candidates)
        (message "vastai: no offers matched those filters")
      (let* ((choice (completing-read "Offer: " candidates nil t))
             (id (vastai--offer-id-from-candidate choice))
             (offer (seq-find (lambda (o)
                                (equal (format "%s" (alist-get 'id o)) id))
                              offers)))
        (setq vastai--current-offer offer)
        (vastai--display (format "Offer %s" id)
                         (vastai--offer-details offer))
        (vastai--offer-action id)))))

(defun vastai--fetch-templates ()
  "Fetch list of templates from the API. Returns vector of alists.

The endpoint requires JSON-encoded `select_cols' and `select_filters'
query parameters; without them the API responds with HTTP 400."
  (let ((result (vastai--request
                 "GET" "/api/v0/template/"
                 '(("select_cols" "[\"*\"]")
                   ("select_filters" "{}")))))
    (when result
      (or (alist-get 'templates result) []))))

(defun vastai--format-template (template)
  "Format TEMPLATE alist as a completing-read candidate string."
  (format "%s | %s | %s"
          (alist-get 'name template "")
          (alist-get 'image template "")
          (alist-get 'hash_id template "")))

(defun vastai--template-details (template)
  "Format TEMPLATE alist as a human-readable detail string."
  (vastai--format-alist
   (seq-filter (lambda (pair) (not (null (cdr pair))))
               (list (cons "Name"    (alist-get 'name template))
                     (cons "Image"   (alist-get 'image template))
                     (cons "Hash ID" (alist-get 'hash_id template))
                     (cons "Disk"    (when (alist-get 'recommended_disk_space template)
                                       (format "%s GB"
                                               (alist-get 'recommended_disk_space
                                                          template))))
                     (cons "SSH"     (when (alist-get 'use_ssh template)
                                       (format "%s" (alist-get 'use_ssh template))))
                     (cons "Created" (alist-get 'recent_create_date template))))))

(defun vastai-list-templates ()
  "List Vast.ai templates via completing-read and show details of selection."
  (interactive)
  (let* ((templates (vastai--fetch-templates))
         (candidates (mapcar #'vastai--format-template templates)))
    (if (seq-empty-p candidates)
        (message "vastai: no templates found")
      (let* ((choice (completing-read "Template: " candidates nil t))
             (parts (split-string choice " | " t))
             (name (car parts))
             (hash-id (nth 2 parts))
             (template (seq-find (lambda (tmpl)
                                   (equal (alist-get 'hash_id tmpl) hash-id))
                                 templates)))
        (vastai--display (format "Template: %s" name)
                         (vastai--template-details template))))))

(defun vastai--fetch-charges (days)
  "Fetch charges for the last DAYS days. Returns vector of alists."
  (let* ((now (float-time))
         (start (- now (* days 86400)))
         (params `(("select_filters"
                    ,(json-encode `((day . ((gte . ,(round start))
                                           (lte . ,(round now)))))))
                   ("latest_first" "true")
                   ("limit" "100")))
         (result (vastai--request "GET" "/api/v0/charges/" params)))
    (when result
      (or (alist-get 'results result) []))))

(defun vastai--format-charge (charge)
  "Format a CHARGE alist as a single display line."
  (format "%-10s %-18s $%8.3f  %s"
          (or (alist-get 'type charge) "")
          (or (alist-get 'source charge) "")
          (or (alist-get 'amount charge) 0.0)
          (or (alist-get 'description charge) "")))

(defun vastai-show-costs ()
  "Fetch and display recent Vast.ai charges in the *vastai* buffer."
  (interactive)
  (let* ((days-str (read-string "Days to show (default 7): " nil nil "7"))
         (days (string-to-number days-str))
         (charges (vastai--fetch-charges days))
         (total (seq-reduce (lambda (acc c)
                              (+ acc (or (alist-get 'amount c) 0.0)))
                            charges 0.0)))
    (if (seq-empty-p charges)
        (message "vastai: no charges found for last %d days" days)
      (vastai--display
       (format "Charges — last %d days" days)
       (concat (mapconcat #'vastai--format-charge charges "\n")
               (format "\n\n%-34s $%8.3f" "TOTAL" total))))))

;;;###autoload (autoload 'vastai "vastai" "Vast.ai GPU cloud management." t)
(transient-define-prefix vastai ()
  "Vast.ai GPU cloud management."
  ["Instances"
   ("l" "List & act on instances" vastai-list-instances)]
  ["Search"
   ("s" "Search offers"           vastai-search-offers)
   ("T" (lambda ()
          (format "Toggle offer type (now %s)"
                  (if (equal vastai-offer-type "bid")
                      "interruptible" "on-demand")))
    vastai-toggle-offer-type :transient t)]
  ["Templates"
   ("t" "List & select template"  vastai-list-templates)]
  ["Costs"
   ("c" "Show recent charges"     vastai-show-costs)]
  (interactive)
  (transient-setup 'vastai))

(provide 'vastai)
;;; vastai.el ends here
