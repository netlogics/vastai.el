;;; vastai-test.el --- ERT tests for vastai.el -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'seq)
(require 'cl-lib)
(require 'vastai)

(ert-deftest vastai-test-api-key-from-custom-var ()
  "Returns key from vastai-api-key when set."
  (let ((vastai-api-key "test-key-from-var"))
    (should (equal (vastai--api-key) "test-key-from-var"))))

(ert-deftest vastai-test-api-key-from-file ()
  "Returns key from file when vastai-api-key is nil."
  (let ((vastai-api-key nil)
        (tmp (make-temp-file "vastai-test-key")))
    (unwind-protect
        (progn
          (write-region "file-key-abc\n" nil tmp)
          (let ((vastai-api-key-file tmp))
            (should (equal (vastai--api-key) "file-key-abc"))))
      (delete-file tmp))))

(ert-deftest vastai-test-api-key-missing ()
  "Signals user-error when neither var nor file provides a key."
  (let ((vastai-api-key nil)
        (vastai-api-key-file "/nonexistent/path/key"))
    (should-error (vastai--api-key) :type 'user-error)))

(ert-deftest vastai-test-build-url-no-params ()
  "Builds URL from base and endpoint with no params."
  (should (equal (vastai--build-url "/api/v1/instances/")
                 "https://console.vast.ai/api/v1/instances/")))

(ert-deftest vastai-test-build-url-with-params ()
  "Builds URL with query params appended."
  (let ((result (vastai--build-url "/api/v0/charges/" '(("limit" "5")))))
    (should (string-prefix-p "https://console.vast.ai/api/v0/charges/?" result))
    (should (string-match-p "limit=5" result))))

(ert-deftest vastai-test-parse-json-response ()
  "Parses JSON body from a simulated HTTP response buffer."
  (let ((buf (generate-new-buffer " *vastai-test-response*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n")
          (insert "{\"instances\":[{\"id\":123}]}")
          (let ((result (vastai--parse-json-response buf)))
            (should (equal (alist-get 'instances result)
                           '[((id . 123))]))))
      (kill-buffer buf))))

(ert-deftest vastai-test-parse-json-response-error-status ()
  "Returns nil and messages on non-2xx HTTP status."
  (let ((buf (generate-new-buffer " *vastai-test-error-response*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\n\r\n")
          (insert "{\"error\":\"Unauthorized\"}")
          (should (null (vastai--parse-json-response buf))))
      (kill-buffer buf))))

(ert-deftest vastai-test-display ()
  "Opens *vastai* buffer with title and content."
  (vastai--display "Test Title" "line one\nline two")
  (unwind-protect
      (with-current-buffer "*vastai*"
        (let ((text (buffer-string)))
          (should (string-match-p "Test Title" text))
          (should (string-match-p "line one" text))
          (should (string-match-p "line two" text))))
    (kill-buffer "*vastai*")))

(ert-deftest vastai-test-format-alist ()
  "Formats an alist as aligned key: value lines."
  (let ((result (vastai--format-alist '((Status . "running") (GPU . "RTX 4090")))))
    (should (string-match-p "Status" result))
    (should (string-match-p "running" result))
    (should (string-match-p "GPU" result))
    (should (string-match-p "RTX 4090" result))))

(ert-deftest vastai-test-format-instance ()
  "Formats an instance alist into a completing-read candidate string."
  (let ((instance '((id . 12345678)
                    (actual_status . "running")
                    (num_gpus . 1)
                    (gpu_name . "RTX 4090")
                    (dph_total . 0.35)
                    (label . "my-label"))))
    (let ((result (vastai--format-instance instance)))
      (should (string-match-p "12345678" result))
      (should (string-match-p "running" result))
      (should (string-match-p "RTX 4090" result))
      (should (string-match-p "0.35" result)))))

(ert-deftest vastai-test-instance-id-from-candidate ()
  "Extracts instance ID from a formatted candidate string."
  (let ((candidate "12345678 | running | 1x RTX 4090 | $0.3500/hr | my-label"))
    (should (equal (vastai--instance-id-from-candidate candidate) "12345678"))))

(ert-deftest vastai-test-parse-filters-simple ()
  "Parses key=value pairs into an alist with eq sub-alists."
  (let ((result (vastai--parse-filters "gpu_name=RTX_4090 num_gpus=1")))
    (should (equal (alist-get "gpu_name" result nil nil #'equal)
                   '((eq . "RTX 4090"))))
    (should (equal (alist-get "num_gpus" result nil nil #'equal)
                   '((eq . "1")))))
  ;; Quoted value preserves underscores
  (let ((result2 (vastai--parse-filters "image_uuid=\"some_id_v1\"")))
    (should (equal (alist-get "image_uuid" result2 nil nil #'equal)
                   '((eq . "some_id_v1"))))))

(ert-deftest vastai-test-parse-filters-empty ()
  "Returns nil for empty or nil filter string."
  (should (null (vastai--parse-filters "")))
  (should (null (vastai--parse-filters nil))))

(ert-deftest vastai-test-format-offer ()
  "Formats an offer alist into a completing-read candidate string."
  (let ((offer '((id . 99887766)
                 (gpu_name . "RTX 4090")
                 (num_gpus . 1)
                 (dph_total . 0.29)
                 (geolocation . "US"))))
    (let ((result (vastai--format-offer offer)))
      (should (string-match-p "99887766" result))
      (should (string-match-p "RTX 4090" result))
      (should (string-match-p "0.29" result))
      (should (string-match-p "US" result)))))

(ert-deftest vastai-test-offer-id-from-candidate ()
  "Extracts offer ID from a formatted candidate string."
  (let ((candidate "99887766 | 1x RTX 4090 | $0.2900/hr | US"))
    (should (equal (vastai--offer-id-from-candidate candidate) "99887766"))))

(ert-deftest vastai-test-format-template ()
  "Formats a template alist into a completing-read candidate string."
  (let ((template '((name . "my-pytorch")
                    (image . "vastai/pytorch:latest")
                    (hash_id . "abc123def456"))))
    (let ((result (vastai--format-template template)))
      (should (string-match-p "my-pytorch" result))
      (should (string-match-p "vastai/pytorch:latest" result))
      (should (string-match-p "abc123def456" result)))))

(ert-deftest vastai-test-build-search-body-default-type ()
  "Search body defaults to the on-demand offer type."
  (should (equal (alist-get 'type (vastai--build-search-body nil))
                 "on-demand")))

(ert-deftest vastai-test-build-search-body-explicit-type ()
  "An explicit OFFER-TYPE argument overrides the default."
  (should (equal (alist-get 'type (vastai--build-search-body nil "bid"))
                 "bid")))

(ert-deftest vastai-test-build-search-body-honors-custom ()
  "Search body follows `vastai-offer-type' when no arg is given."
  (let ((vastai-offer-type "reserved"))
    (should (equal (alist-get 'type (vastai--build-search-body nil))
                   "reserved"))))

(ert-deftest vastai-test-build-search-body-merges-user-filters ()
  "User filters are appended without dropping the base filters."
  (let ((body (vastai--build-search-body
               '(("gpu_name" . ((eq . "RTX 4090")))))))
    (should (equal (alist-get "gpu_name" body nil nil #'equal)
                   '((eq . "RTX 4090"))))
    (should (equal (alist-get 'type body) "on-demand"))
    (should (equal (alist-get 'rentable body) '((eq . t))))
    (should (equal (alist-get 'order body) [["score" "desc"]]))))

(ert-deftest vastai-test-toggle-offer-type ()
  "Toggling flips between on-demand and bid."
  (let ((vastai-offer-type "on-demand"))
    (vastai-toggle-offer-type)
    (should (equal vastai-offer-type "bid"))
    (vastai-toggle-offer-type)
    (should (equal vastai-offer-type "on-demand"))))

(ert-deftest vastai-test-format-charge ()
  "Formats a charge using the real API field names."
  (let ((charge '((type . "instance")
                  (source . "instance-54511469")
                  (amount . 0.023)
                  (description . "Instance 54511469 Charges - 1 day"))))
    (let ((result (vastai--format-charge charge)))
      (should (string-match-p "instance" result))
      (should (string-match-p "instance-54511469" result))
      (should (string-match-p "0.023" result))
      (should (string-match-p "Charges - 1 day" result)))))

(ert-deftest vastai-test-parse-json-response-surfaces-error-message ()
  "A non-2xx response surfaces the server's error message."
  (let ((buf (generate-new-buffer " *vastai-test-errmsg*"))
        (messages nil))
    (unwind-protect
        (with-current-buffer buf
          (insert "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\n\r\n")
          (insert "{\"success\":false,\"msg\":\"invalid api key\"}")
          (cl-letf (((symbol-function 'message)
                     (lambda (fmt &rest args)
                       (push (apply #'format fmt args) messages))))
            (should (null (vastai--parse-json-response buf)))
            (should (seq-some (lambda (m) (string-match-p "invalid api key" m))
                              messages))))
      (kill-buffer buf))))

(provide 'vastai-test)
;;; vastai-test.el ends here
