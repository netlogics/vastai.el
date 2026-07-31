;;; vastai-test.el --- ERT tests for vastai.el -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
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

(provide 'vastai-test)
;;; vastai-test.el ends here
