;;; slang-ts-mode-tests.el --- Tests for slang-ts-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Vostranox

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; ERT tests for `slang-ts-mode'.  Run from the repository root with:
;;
;;   emacs -Q -batch -L . -l test/slang-ts-mode-tests.el -f ert-run-tests-batch-and-exit
;;

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'treesit)

(defvar slang-ts-test--here
  (file-name-directory (or load-file-name buffer-file-name)))

(defun slang-ts-test--ensure-grammar ()
  "Make the Slang grammar loadable, compiling it if necessary.
Return non-nil if the grammar is available."
  (let ((lib-dir (expand-file-name "../.scratch/ts" slang-ts-test--here)))
    (when (file-directory-p lib-dir)
      (add-to-list 'treesit-extra-load-path lib-dir))
    (or (treesit-ready-p 'slang t)
        (let* ((grammar-dir
                (or (getenv "TREE_SITTER_SLANG_DIR")
                    (expand-file-name "../../tree-sitter-slang"
                                      slang-ts-test--here)))
               (parser-c (expand-file-name "src/parser.c" grammar-dir))
               (scanner-c (expand-file-name "src/scanner.c" grammar-dir))
               (lib (expand-file-name "libtree-sitter-slang.so" lib-dir)))
          (when (file-readable-p parser-c)
            (make-directory lib-dir t)
            (with-temp-buffer
              (let ((status (call-process
                             "cc" nil t nil "-fPIC" "-shared" "-O2"
                             "-I" (expand-file-name "src" grammar-dir)
                             parser-c scanner-c "-o" lib)))
                (unless (zerop status)
                  (message "Grammar compilation failed: %s"
                           (buffer-string)))))
            (add-to-list 'treesit-extra-load-path lib-dir)
            (treesit-ready-p 'slang t))))))

(slang-ts-test--ensure-grammar)
(require 'slang-ts-mode)

(defmacro slang-ts-test--with-file (&rest body)
  "Run BODY in a `slang-ts-mode' buffer visiting test.slang."
  `(with-temp-buffer
     (skip-unless (treesit-ready-p 'slang t))
     (insert-file-contents (expand-file-name "test.slang"
                                             slang-ts-test--here))
     (slang-ts-mode)
     (setq-local case-fold-search nil)
     (setq-local treesit-font-lock-level 4)
     (treesit-font-lock-recompute-features)
     (font-lock-ensure)
     ,@body))

(defun slang-ts-test--face-at (text &optional offset)
  "Return the face at the start of the first occurrence of TEXT.
With OFFSET, look that many characters past the match start."
  (goto-char (point-min))
  (search-forward text)
  (get-text-property (+ (match-beginning 0) (or offset 0)) 'face))

(ert-deftest slang-ts-mode-activates ()
  (slang-ts-test--with-file
   (should (eq major-mode 'slang-ts-mode))
   (should (treesit-parser-list))
   (should (eq (treesit-parser-language (car (treesit-parser-list)))
               'slang))))

(ert-deftest slang-ts-mode-fixture-parses-cleanly ()
  "Fixture test.slang must contain no ERROR or missing nodes."
  (slang-ts-test--with-file
   (let ((bad 0))
     (cl-labels ((walk (node)
                   (when (or (treesit-node-check node 'missing)
                             (equal (treesit-node-type node) "ERROR"))
                     (setq bad (1+ bad)))
                   (dolist (child (treesit-node-children node))
                     (walk child))))
       (walk (treesit-buffer-root-node)))
     (should (= bad 0)))))

(ert-deftest slang-ts-mode-comment-settings ()
  (slang-ts-test--with-file
   (should (equal comment-start "// "))
   (should (equal comment-end ""))))

(ert-deftest slang-ts-mode-font-lock-keywords ()
  (slang-ts-test--with-file
   (should (eq (slang-ts-test--face-at "interface IShape")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "extension Sphere")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "associatedtype Payload")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "property highBits")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "__init(")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "__subscript(")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "var contribution")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "let scale")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "where T : IShape")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "discard;")
               'font-lock-keyword-face))
   (should (eq (slang-ts-test--face-at "light is DirectionalLight" 6)
               'font-lock-keyword-face))))

(ert-deftest slang-ts-mode-font-lock-types ()
  (slang-ts-test--with-file
   (should (eq (slang-ts-test--face-at "IShape\n")
               'font-lock-type-face))
   (should (eq (slang-ts-test--face-at "This other")
               'font-lock-type-face))
   (should (eq (slang-ts-test--face-at "IArithmetic")
               'font-lock-type-face))
   (should (eq (slang-ts-test--face-at "light as DirectionalLight" 9)
               'font-lock-type-face))
   (should (eq (slang-ts-test--face-at "float3 normal")
               'font-lock-type-face))
   (should (eq (slang-ts-test--face-at "RWTexture2D")
               'font-lock-type-face))))

(ert-deftest slang-ts-mode-font-lock-semantics ()
  (slang-ts-test--with-file
   (should (eq (slang-ts-test--face-at "SV_DispatchThreadID")
               'font-lock-constant-face))
   (should (eq (slang-ts-test--face-at "SV_Target")
               'font-lock-constant-face))
   (should (eq (slang-ts-test--face-at ": POSITION" 2)
               'font-lock-constant-face))))

(ert-deftest slang-ts-mode-font-lock-attributes ()
  (slang-ts-test--with-file
   (should (eq (slang-ts-test--face-at "numthreads")
               'font-lock-preprocessor-face))
   (should (eq (slang-ts-test--face-at "shader(\"fragment\")")
               'font-lock-preprocessor-face))
   (should (eq (slang-ts-test--face-at "\"fragment\"")
               'font-lock-string-face))))

(ert-deftest slang-ts-mode-font-lock-functions ()
  (slang-ts-test--with-file
   ;; Definitions.
   (should (eq (slang-ts-test--face-at "fragmentMain(float3")
               'font-lock-function-name-face))
   (should (eq (slang-ts-test--face-at "genericMax<T")
               'font-lock-function-name-face))
   ;; Calls.
   (should (eq (slang-ts-test--face-at "evalLight(gLight")
               'font-lock-function-call-face))
   ;; Intrinsics.
   (should (eq (slang-ts-test--face-at "saturate(")
               'font-lock-builtin-face))
   (should (eq (slang-ts-test--face-at "gAlbedo.Sample" 8)
               'font-lock-builtin-face))))

(ert-deftest slang-ts-mode-font-lock-literals-and-preproc ()
  (slang-ts-test--with-file
   (should (eq (slang-ts-test--face-at "0xFFFF")
               'font-lock-number-face))
   (should (eq (slang-ts-test--face-at "3.14159265f")
               'font-lock-number-face))
   (should (eq (slang-ts-test--face-at "\"sphere")
               'font-lock-string-face))
   (should (eq (slang-ts-test--face-at "\\n")
               'font-lock-escape-face))
   (should (eq (slang-ts-test--face-at "#define")
               'font-lock-preprocessor-face))
   (should (eq (slang-ts-test--face-at "MAX_LIGHTS")
               'font-lock-variable-name-face))
   (should (eq (slang-ts-test--face-at "// namespace Demo")
               'font-lock-comment-face))))

(ert-deftest slang-ts-mode-font-lock-imports ()
  (slang-ts-test--with-file
   (should (eq (slang-ts-test--face-at "import Graphics.Core" 7)
               'font-lock-constant-face))
   (should (eq (slang-ts-test--face-at "__exported")
               'font-lock-keyword-face))))

(ert-deftest slang-ts-mode-font-lock-toplevel-resources ()
  "All top-level resource declarations get definition faces.
The grammar parses them as bare type + expression statement, and
anchored queries would only fontify the first per parent."
  (slang-ts-test--with-file
   (dolist (name '("gLight" "gPositions" "gOutput" "gSampler" "gAlbedo"))
     (should (eq (slang-ts-test--face-at name)
                 'font-lock-variable-name-face)))))

(ert-deftest slang-ts-mode-font-lock-where-constraint ()
  "The trailing constraint of a multi-constraint where clause.
It mis-parses as a semantics node but must be fontified as a
type, not a constant."
  (slang-ts-test--with-file
   (should (eq (slang-ts-test--face-at "T : IDifferentiable" 4)
               'font-lock-type-face))))

(ert-deftest slang-ts-mode-indent-round-trip ()
  "Reindenting the whole canonical fixture must be a no-op."
  (slang-ts-test--with-file
   (let ((original (buffer-string)))
     (indent-region (point-min) (point-max))
     (should (equal (buffer-string) original)))))

(ert-deftest slang-ts-mode-indent-from-scratch ()
  "Indenting flattened code must reproduce the canonical layout."
  (slang-ts-test--with-file
   (let ((original (buffer-string)))
     (goto-char (point-min))
     (while (re-search-forward (rx bol (+ (in " \t"))) nil t)
       (let ((beg (match-beginning 0))
             (end (match-end 0)))
         (unless (save-excursion
                   (save-match-data (nth 4 (syntax-ppss beg))))
           (delete-region beg end))))
     (indent-region (point-min) (point-max))
     (should (equal (buffer-string) original)))))

(ert-deftest slang-ts-mode-indent-attributed-statement ()
  "A loop attribute and its statement keyword align."
  (with-temp-buffer
    (skip-unless (treesit-ready-p 'slang t))
    (insert "void f()\n{\n[unroll]\nfor (int i = 0; i < 4; ++i)\nx += i;\n}\n")
    (slang-ts-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   (concat "void f()\n{\n    [unroll]\n"
                           "    for (int i = 0; i < 4; ++i)\n"
                           "        x += i;\n}\n")))))

(ert-deftest slang-ts-mode-generics-sexp-motion ()
  "Angle brackets of generics pair up for sexp motion."
  (with-temp-buffer
    (skip-unless (treesit-ready-p 'slang t))
    (insert "StructuredBuffer<Optional<float4>> gData;\n")
    (slang-ts-mode)
    (syntax-ppss-flush-cache (point-min))
    (syntax-propertize (point-max))
    (goto-char (point-min))
    (search-forward "<")
    (backward-char)
    (forward-sexp)
    (should (eq (char-before) ?>))
    (should (looking-at-p " gData"))))

(ert-deftest slang-ts-mode-imenu ()
  (slang-ts-test--with-file
   (let* ((index (funcall imenu-create-index-function))
          (categories (mapcar #'car index))
          (names (lambda (cat)
                   (mapcar #'car (cdr (assoc cat index))))))
     (should (member "Interface" categories))
     (should (member "Struct" categories))
     (should (member "Extension" categories))
     (should (member "Function" categories))
     (should (member "IShape" (funcall names "Interface")))
     (should (member "Sphere" (funcall names "Struct")))
     (should (member "Light" (funcall names "Struct")))
     (should (member "LightKind" (funcall names "Enum")))
     (should (member "fragmentMain" (funcall names "Function")))
     (should (member "computeMain" (funcall names "Function")))
     (should (member "gLight" (funcall names "Variable")))
     (should (member "highBits" (funcall names "Property"))))))

(ert-deftest slang-ts-mode-defun-navigation ()
  (slang-ts-test--with-file
   (goto-char (point-min))
   (search-forward "return saturate")
   (should (equal (treesit-defun-name
                   (treesit-defun-at-point))
                  "evalLight"))
   (beginning-of-defun)
   (should (looking-at (rx "float evalLight")))))

(ert-deftest slang-ts-mode-defun-name-slang-constructs ()
  "Slang-specific defun nodes report their names.
Navigation uses the top-level tactic, so query the name function
directly on the nested member nodes."
  (slang-ts-test--with-file
   (cl-flet ((enclosing (text type)
               (goto-char (point-min))
               (search-forward text)
               (treesit-parent-until
                (treesit-node-at (point))
                (lambda (node)
                  (equal (treesit-node-type node) type))
                t)))
     (should (equal (slang-ts-mode--defun-name
                     (enclosing "radius = r" "init_declaration"))
                    "__init"))
     (should (equal (slang-ts-mode--defun-name
                     (enclosing "return flags >> 16" "property_declaration"))
                    "highBits")))))

;;; slang-ts-mode-tests.el ends here
