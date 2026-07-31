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

(provide 'vastai-test)
;;; vastai-test.el ends here
