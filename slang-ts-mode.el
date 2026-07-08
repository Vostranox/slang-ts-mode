;;; slang-ts-mode.el --- Tree-sitter major mode for Slang shader files -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Vostranox
;; Portions adapted from GNU Emacs (c-ts-mode.el),
;; Copyright (C) 2022-2025 Free Software Foundation, Inc.

;; Author: Vostranox <vostranox@gmail.com>
;; Maintainer: Vostranox <vostranox@gmail.com>
;; Keywords: languages
;; Version: 1.0
;; Package-Requires: ((emacs "30.1"))
;; URL: https://github.com/Vostranox/slang-ts-mode

;; This file is NOT part of GNU Emacs.

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

;; A tree-sitter based major mode for the Slang shading language (https://shader-slang.org).
;;
;; This mode requires the tree-sitter grammar from
;; https://github.com/theHamsta/tree-sitter-slang.  If it is not
;; installed yet, run `M-x slang-ts-mode-install-grammar'.

;;; Code:

(require 'treesit)
(require 'c-ts-common)
(eval-when-compile (require 'rx))

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-node-parent "treesit.c")
(declare-function treesit-node-start "treesit.c")
(declare-function treesit-node-end "treesit.c")
(declare-function treesit-node-child "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-prev-sibling "treesit.c")
(declare-function treesit-node-first-child-for-pos "treesit.c")
(declare-function treesit-node-eq "treesit.c")

(defgroup slang-ts nil
  "Major mode for editing Slang shader files, powered by tree-sitter."
  :group 'languages
  :prefix "slang-ts-")

(defcustom slang-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `slang-ts-mode'."
  :type 'integer
  :safe 'integerp
  :group 'slang-ts)

(defvar slang-ts-mode-grammar-source
  '(slang "https://github.com/theHamsta/tree-sitter-slang")
  "Recipe for `treesit-language-source-alist' to build the Slang grammar.")

(unless (assq 'slang treesit-language-source-alist)
  (add-to-list 'treesit-language-source-alist slang-ts-mode-grammar-source))

;;;###autoload
(defun slang-ts-mode-install-grammar ()
  "Install the tree-sitter grammar for Slang.
The grammar is built from `slang-ts-mode-grammar-source' using
`treesit-install-language-grammar'."
  (interactive)
  (unless (assq 'slang treesit-language-source-alist)
    (add-to-list 'treesit-language-source-alist slang-ts-mode-grammar-source))
  (treesit-install-language-grammar 'slang))

(defvar slang-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_  "_"      table)
    (modify-syntax-entry ?\\ "\\"     table)
    (modify-syntax-entry ?+  "."      table)
    (modify-syntax-entry ?-  "."      table)
    (modify-syntax-entry ?=  "."      table)
    (modify-syntax-entry ?%  "."      table)
    (modify-syntax-entry ?<  "."      table)
    (modify-syntax-entry ?>  "."      table)
    (modify-syntax-entry ?&  "."      table)
    (modify-syntax-entry ?|  "."      table)
    (modify-syntax-entry ?\' "\""     table)
    (modify-syntax-entry ?\240 "."    table)
    (modify-syntax-entry ?/  ". 124b" table)
    (modify-syntax-entry ?*  ". 23"   table)
    (modify-syntax-entry ?\n "> b"    table)
    (modify-syntax-entry ?\^m "> b"   table)
    table)
  "Syntax table for `slang-ts-mode'.")

(defun slang-ts-mode--syntax-propertize (beg end)
  "Apply syntax text property to template delimiters between BEG and END.

< and > are usually punctuation, e.g., in ->.  But when used for
generics, they should be considered pairs.

This function checks for < and > between BEG and END and
applies the appropriate text property to alter the syntax of
template delimiters < and >'s."
  (goto-char beg)
  (while (re-search-forward (rx (or "<" ">")) end t)
    (pcase (treesit-node-type
            (treesit-node-parent
             (treesit-node-at (match-beginning 0))))
      ("template_argument_list"
       (put-text-property (match-beginning 0)
                          (match-end 0)
                          'syntax-table
                          (pcase (char-before)
                            (?< '(4 . ?>))
                            (?> '(5 . ?<))))))))

;;; Indentation

(defun slang-ts-mode--anchor-prev-sibling (node parent bol &rest _)
  "Return the start of the previous named sibling of NODE.

This anchor handles the special case where the previous sibling
is a labeled_statement or a preprocessor directive, in which case
it returns the position of the relevant inner node instead.

Return nil if a) there is no previous sibling, or b) the previous
sibling doesn't have a child.

PARENT is NODE's parent, BOL is the beginning of non-whitespace
characters of the current line."
  (when-let* ((prev-sibling
               (or (treesit-node-prev-sibling node t)
                   (treesit-node-prev-sibling
                    (treesit-node-first-child-for-pos parent bol) t)
                   (treesit-node-child parent -1 t)))
              (continue t))
    (save-excursion
      (while (and prev-sibling continue)
        (pcase (treesit-node-type prev-sibling)
          ("labeled_statement"
           (setq prev-sibling (treesit-node-child prev-sibling 2)))
          ((or "preproc_if" "preproc_ifdef")
           (setq prev-sibling (treesit-node-child prev-sibling -2)))
          ((or "preproc_elif" "preproc_else")
           (setq prev-sibling (treesit-node-child prev-sibling -1)))
          ((or "#elif" "#else")
           (setq prev-sibling (treesit-node-prev-sibling
                               (treesit-node-parent prev-sibling) t)))
          (_ (goto-char (treesit-node-start prev-sibling))
             (if (or (looking-back (rx bol (* whitespace))
                                   (line-beginning-position))
                     (treesit-node-eq (treesit-node-child parent 0 t)
                                      prev-sibling))
                 (setq continue nil)
               (setq prev-sibling
                     (treesit-node-prev-sibling prev-sibling)))))))
    (treesit-node-start prev-sibling)))

(defun slang-ts-mode--standalone-grandparent (_node parent bol &rest args)
  "Like the standalone-parent anchor but pass it the grandparent.
PARENT is NODE's parent, BOL is the beginning of non-whitespace
characters of the current line, ARGS are the remaining arguments
given to the anchor function."
  (apply (alist-get 'standalone-parent treesit-simple-indent-presets)
         parent (treesit-node-parent parent) bol args))

(defun slang-ts-mode--first-sibling (node parent &rest _)
  "Matches when NODE is the \"first sibling\".
\"First sibling\" is defined as: the first child node of PARENT
such that it's on its own line.  NODE is the node to match and
PARENT is its parent."
  (let ((prev-sibling (treesit-node-prev-sibling node t)))
    (or (null prev-sibling)
        (save-excursion
          (goto-char (treesit-node-start prev-sibling))
          (<= (line-beginning-position)
              (treesit-node-start parent)
              (line-end-position))))))

(defun slang-ts-mode--else-heuristic (node _parent _bol &rest _)
  "Heuristic matcher for when \"else\" is followed by a closing bracket.
NODE is the node to match; see `treesit-simple-indent-rules'."
  (and (null node)
       (save-excursion
         (forward-line -1)
         (looking-at (rx (* whitespace) "else" (* whitespace) eol)))))

(defun slang-ts-mode--accessor-group-p (node _parent _bol &rest _)
  "Matches when NODE is the accessor group of a property or subscript.
The grammar splits `property'/`__subscript' bodies into three
sibling nodes aliased as compound_statement: the opening brace,
the group of `get'/`set' accessors, and the closing brace.  This
matcher matches only the middle one, which starts at the first
accessor rather than at a brace and therefore needs an
indentation step of its own.  The brace nodes are childless
aliased tokens, so requiring a child rules them out."
  (and (equal (treesit-node-type node) "compound_statement")
       (treesit-node-child node 0)
       t))

(defun slang-ts-mode--before-indent (args)
  "Normalize the (NODE PARENT BOL) list in ARGS before indenting.
When the parser's error recovery produces a zero-width \"virtual\"
closing brace, indent relative to that brace's parent instead."
  (pcase-let ((`(,node ,parent ,bol) args))
    (when (null node)
      (let ((smallest-node (treesit-node-at (point))))
        (when (and (equal (treesit-node-type smallest-node) "}")
                   (equal (treesit-node-end smallest-node)
                          (treesit-node-start smallest-node)))
          (setq parent (treesit-node-parent smallest-node)))))
    (list node parent bol)))

(defvar slang-ts-mode--indent-rules
  `((slang
     (slang-ts-mode--else-heuristic prev-line slang-ts-mode-indent-offset)

     ((parent-is "translation_unit") column-0 0)
     ((query "(ERROR (ERROR)) @indent") column-0 0)
     ((node-is ")") parent 1)
     ((node-is "]") parent-bol 0)
     ((node-is "else") parent-bol 0)
     ((node-is "case") parent-bol 0)
     ((node-is "preproc_arg") no-indent)
     ((and (parent-is "comment") c-ts-common-looking-at-star)
      c-ts-common-comment-start-after-first-star -1)
     (c-ts-common-comment-2nd-line-matcher
      c-ts-common-comment-2nd-line-anchor
      1)
     ((parent-is "comment") prev-adaptive-prefix 0)

     ((node-is "labeled_statement") standalone-parent 0)
     ((parent-is "labeled_statement")
      slang-ts-mode--standalone-grandparent slang-ts-mode-indent-offset)

     ((node-is "preproc") column-0 0)
     ((node-is "#endif") column-0 0)
     ((match "preproc_call" "compound_statement") column-0 0)
     ((n-p-gp nil "preproc" "translation_unit") column-0 0)
     ((match nil ,(rx "preproc_" (or "if" "elif")) nil 3 3)
      standalone-parent slang-ts-mode-indent-offset)
     ((match nil "preproc_ifdef" nil 2 2)
      standalone-parent slang-ts-mode-indent-offset)
     ((match nil "preproc_else" nil 1 1)
      standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "preproc") slang-ts-mode--anchor-prev-sibling 0)

     ((parent-is "function_definition") parent-bol 0)
     ((parent-is ,(rx bos "declaration" eos)) parent-bol 0)
     ((parent-is "conditional_expression") first-sibling 0)
     ((parent-is "assignment_expression") parent-bol slang-ts-mode-indent-offset)
     ((parent-is "concatenated_string") first-sibling 0)
     ((parent-is "comma_expression") first-sibling 0)
     ((parent-is "init_declarator") parent-bol slang-ts-mode-indent-offset)
     ((parent-is "parenthesized_expression") first-sibling 1)
     ((parent-is ,(rx bos "argument_list" eos)) first-sibling 1)
     ((parent-is "parameter_list") first-sibling 1)
     ((parent-is "template_argument_list") first-sibling 1)
     ((parent-is "binary_expression") parent 0)
     ((query "(for_statement initializer: (_) @indent)") parent-bol 5)
     ((query "(for_statement condition: (_) @indent)") parent-bol 5)
     ((query "(for_statement update: (_) @indent)") parent-bol 5)
     ((query "(call_expression arguments: (_) @indent)")
      parent slang-ts-mode-indent-offset)
     ((parent-is "call_expression") parent 0)

     ((node-is "where_clause") parent-bol slang-ts-mode-indent-offset)
     ((parent-is "where_clause") parent-bol slang-ts-mode-indent-offset)
     ((node-is "semantics") parent-bol slang-ts-mode-indent-offset)
     ((node-is "base_class_clause") parent-bol slang-ts-mode-indent-offset)

     ((node-is "}") standalone-parent 0)
     ((node-is "access_specifier") parent-bol 0)
     ((node-is ,(rx bos "declaration_list" eos)) standalone-parent 0)
     ((parent-is ,(rx bos "declaration_list" eos))
      standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "template_declaration") parent-bol 0)

     ((match nil "initializer_list" nil 1 1)
      parent-bol slang-ts-mode-indent-offset)
     ((parent-is "initializer_list") slang-ts-mode--anchor-prev-sibling 0)
     ((node-is "enumerator_list") standalone-parent 0)
     ((match nil "enumerator_list" nil 1 1)
      standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "enumerator_list") slang-ts-mode--anchor-prev-sibling 0)
     ((node-is "field_declaration_list") standalone-parent 0)
     ((match nil "field_declaration_list" nil 1 1)
      standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "field_declaration_list") slang-ts-mode--anchor-prev-sibling 0)

     ((match "compound_statement" "if_statement") standalone-parent 0)
     ((match "compound_statement" "else_clause") standalone-parent 0)
     ((match "compound_statement" "for_statement") standalone-parent 0)
     ((match "compound_statement" "while_statement") standalone-parent 0)
     ((match "compound_statement" "do_statement") standalone-parent 0)
     ((match "compound_statement" "switch_statement") standalone-parent 0)
     ((match "compound_statement" "case_statement") standalone-parent 0)
     ((match "compound_statement" "init_declaration") standalone-parent 0)
     ((and (match "compound_statement"
                  ,(rx bos (or "property_declaration"
                               "subscript_declaration")
                       eos))
           slang-ts-mode--accessor-group-p)
      standalone-parent slang-ts-mode-indent-offset)
     ((match "compound_statement" "subscript_declaration") standalone-parent 0)
     ((match "compound_statement" "property_declaration") standalone-parent 0)
     ((match "compound_statement" "property_get") standalone-parent 0)
     ((match "compound_statement" "property_set") standalone-parent 0)

     ((n-p-gp nil "compound_statement"
              ,(rx bos (or "property_declaration" "subscript_declaration")
                   eos))
      slang-ts-mode--anchor-prev-sibling 0)

     ((or (and (parent-is "compound_statement")
               slang-ts-mode--first-sibling)
          (match null "compound_statement"))
      standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "compound_statement") slang-ts-mode--anchor-prev-sibling 0)
     ((node-is "compound_statement") standalone-parent slang-ts-mode-indent-offset)
     ((match "expression_statement" nil "body")
      standalone-parent slang-ts-mode-indent-offset)
     ((match ,(rx bos (or "if" "for" "while" "do" "switch") eos)
             ,(rx bos (or "if" "for" "while" "do" "switch")
                  "_statement" eos))
      parent-bol 0)
     ((parent-is "if_statement") standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "else_clause") standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "for_statement") standalone-parent slang-ts-mode-indent-offset)
     ((match "while" "do_statement") parent-bol 0)
     ((parent-is "while_statement") standalone-parent slang-ts-mode-indent-offset)
     ((parent-is "do_statement") standalone-parent slang-ts-mode-indent-offset)

     ((parent-is "case_statement") standalone-parent slang-ts-mode-indent-offset)))
  "Tree-sitter indent rules for `slang-ts-mode'.")

(defvar slang-ts-mode--keywords
  '("break" "case" "const" "continue" "default" "do" "else" "enum"
    "extern" "for" "goto" "if" "inline" "return" "sizeof" "static"
    "struct" "switch" "typedef" "union" "volatile" "while"
    "catch" "class" "delete" "explicit" "export" "final" "friend"
    "mutable" "namespace" "new" "operator" "override" "private"
    "protected" "public" "template" "throw" "try" "typename" "using"
    "virtual"
    "cbuffer" "centroid" "column_major" "discard" "globallycoherent"
    "groupshared" "in" "inout" "line" "lineadj" "linear"
    "nointerpolation" "noperspective" "out" "point" "precise"
    "register" "row_major" "sample" "shared" "snorm" "triangle"
    "triangleadj" "uniform" "unorm"
    "as" "associatedtype" "dyn" "extension" "get" "import" "interface"
    "is" "let" "module" "property" "set" "some" "var" "where"
    "__exported" "__init" "__subscript")
  "Slang keywords for tree-sitter font-locking.")

(defvar slang-ts-mode--type-keywords
  '("long" "short" "signed" "unsigned")
  "Keywords that should be considered as part of a type.")

(defvar slang-ts-mode--operators
  '("=" "-" "*" "/" "+" "%" "~" "|" "&" "^" "<<" ">>" "->"
    "." "<" "<=" ">=" ">" "==" "!=" "!" "&&" "||" "-="
    "+=" "*=" "/=" "%=" "|=" "&=" "^=" ">>=" "<<=" "--" "++")
  "Slang operators for tree-sitter font-locking.")

(defvar slang-ts-mode--preproc-keywords
  '("#define" "#if" "#ifdef" "#ifndef" "#elifdef" "#elifndef"
    "#else" "#elif" "#endif" "#include")
  "Slang preprocessor keywords for tree-sitter font-locking.")

(defvar slang-ts-mode--intrinsic-functions
  '("abs" "acos" "all" "any" "asin" "atan" "atan2" "ceil" "clamp"
    "clip" "cos" "cosh" "cross" "ddx" "ddx_coarse" "ddx_fine" "ddy"
    "ddy_coarse" "ddy_fine" "degrees" "determinant" "distance" "dot"
    "exp" "exp2" "faceforward" "firstbithigh" "firstbitlow" "floor"
    "fma" "fmod" "frac" "frexp" "fwidth" "isinf" "isnan" "ldexp"
    "length" "lerp" "lit" "log" "log10" "log2" "mad" "max" "min"
    "modf" "mul" "normalize" "pow" "printf" "radians" "rcp" "reflect"
    "refract" "reversebits" "round" "rsqrt" "saturate" "sign" "sin"
    "sincos" "sinh" "smoothstep" "sqrt" "step" "tan" "tanh"
    "transpose" "trunc"
    "AllMemoryBarrier" "AllMemoryBarrierWithGroupSync"
    "DeviceMemoryBarrier" "DeviceMemoryBarrierWithGroupSync"
    "GroupMemoryBarrier" "GroupMemoryBarrierWithGroupSync"
    "InterlockedAdd" "InterlockedAnd" "InterlockedCompareExchange"
    "InterlockedCompareStore" "InterlockedExchange" "InterlockedMax"
    "InterlockedMin" "InterlockedOr" "InterlockedXor"
    "WaveActiveAllEqual" "WaveActiveAllTrue" "WaveActiveAnyTrue"
    "WaveActiveBallot" "WaveActiveBitAnd" "WaveActiveBitOr"
    "WaveActiveBitXor" "WaveActiveCountBits" "WaveActiveMax"
    "WaveActiveMin" "WaveActiveProduct" "WaveActiveSum"
    "WaveGetLaneCount" "WaveGetLaneIndex" "WaveIsFirstLane"
    "WavePrefixCountBits" "WavePrefixProduct" "WavePrefixSum"
    "WaveReadLaneAt" "WaveReadLaneFirst")
  "Slang/HLSL intrinsic functions for tree-sitter font-locking.")

(defvar slang-ts-mode--intrinsic-methods
  '("Sample" "SampleBias" "SampleCmp" "SampleCmpLevelZero" "SampleGrad"
    "SampleLevel" "Load" "Store" "GetDimensions"
    "CalculateLevelOfDetail" "CalculateLevelOfDetailUnclamped"
    "Gather" "GatherAlpha" "GatherBlue" "GatherCmp" "GatherCmpAlpha"
    "GatherCmpBlue" "GatherCmpGreen" "GatherCmpRed" "GatherGreen"
    "GatherRed" "Append" "Consume" "IncrementCounter"
    "DecrementCounter")
  "Slang/HLSL intrinsic methods for tree-sitter font-locking.")

(defun slang-ts-mode--declarator-identifier (node &optional qualified)
  "Return the identifier of the declarator node NODE.
If QUALIFIED is non-nil, include the namespace part of the
identifier and return a qualified_identifier."
  (pcase (treesit-node-type node)
    ((or "attributed_declarator" "parenthesized_declarator")
     (slang-ts-mode--declarator-identifier (treesit-node-child node 0 t)
                                           qualified))
    ((or "pointer_declarator" "reference_declarator")
     (slang-ts-mode--declarator-identifier (treesit-node-child node -1)
                                           qualified))
    ((or "function_declarator" "array_declarator" "init_declarator")
     (slang-ts-mode--declarator-identifier
      (treesit-node-child-by-field-name node "declarator")
      qualified))
    ("type_hinted_declarator"
     (slang-ts-mode--declarator-identifier (treesit-node-child node 0 t)
                                           qualified))
    ((or "template_function" "template_method")
     (slang-ts-mode--declarator-identifier
      (or (treesit-node-child-by-field-name node "name")
          (treesit-node-child node 0 t))
      qualified))
    ("qualified_identifier"
     (if qualified
         node
       (slang-ts-mode--declarator-identifier
        (treesit-node-child-by-field-name node "name")
        qualified)))
    ((or "identifier" "field_identifier")
     node)))

(defun slang-ts-mode--fontify-declarator (node override start end &rest _args)
  "Fontify a declarator (whatever is under the \"declarator\" field).
For NODE, OVERRIDE, START, END, and ARGS, see
`treesit-font-lock-rules'."
  (let* ((identifier (slang-ts-mode--declarator-identifier node))
         (fn-like-root
          (treesit-parent-while
           (treesit-node-parent identifier)
           (lambda (node)
             (member (treesit-node-type node)
                     '("qualified_identifier" "template_function"
                       "template_method" "type_hinted_declarator")))))
         (face (pcase (treesit-node-type (treesit-node-parent
                                          (or fn-like-root
                                              identifier)))
                 ("field_declaration" 'font-lock-property-name-face)
                 ("function_declarator" 'font-lock-function-name-face)
                 (_ 'font-lock-variable-name-face))))
    (when identifier
      (treesit-fontify-with-override
       (treesit-node-start identifier) (treesit-node-end identifier)
       face override start end))))

(defun slang-ts-mode--top-level-variable-p (node)
  "Return non-nil if NODE stands for a top-level resource declaration.
The Slang grammar allows a bare type specifier as a top-level
statement, so declarations like \"Texture2D gAlbedo;\" often
parse as a type node followed by an expression_statement holding
just the variable identifier.  NODE is that expression_statement."
  (and (equal (treesit-node-type node) "expression_statement")
       (member (treesit-node-type (treesit-node-parent node))
               '("translation_unit" "declaration_list"))
       (let ((child (treesit-node-child node 0 t)))
         (and child
              (equal (treesit-node-type child) "identifier")
              (null (treesit-node-next-sibling child t))))
       (member (treesit-node-type (treesit-node-prev-sibling node t))
               '("template_type" "type_identifier" "primitive_type"
                 "sized_type_specifier" "qualified_identifier"
                 "associatedtype_specifier"))))

(defun slang-ts-mode--fontify-variable (node override start end &rest _)
  "Fontify an identifier node if it is a variable use.
Don't fontify it if it is a function identifier.  For NODE,
OVERRIDE, START, END, and ARGS, see `treesit-font-lock-rules'."
  (unless (equal (treesit-node-type (treesit-node-parent node))
                 "call_expression")
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     'font-lock-variable-use-face override start end)))

(defun slang-ts-mode--fontify-toplevel-variable (node override start end &rest _)
  "Fontify NODE as a variable definition if it names a resource.
NODE is the identifier of an expression_statement; it is only
fontified when the statement stands for a top-level resource
declaration (see `slang-ts-mode--top-level-variable-p').  For
OVERRIDE, START, and END, see `treesit-font-lock-rules'."
  (when (slang-ts-mode--top-level-variable-p (treesit-node-parent node))
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     'font-lock-variable-name-face override start end)))

(defun slang-ts-mode--fontify-semantics (node override start end &rest _)
  "Fontify NODE, the identifier of a semantics node.
Semantic annotations are fontified as constants.  The trailing
constraint of a multi-constraint `where' clause mis-parses as a
semantics node in the grammar; fontify that one as a type
instead.  For OVERRIDE, START, and END, see
`treesit-font-lock-rules'."
  (let* ((semantics (treesit-node-parent node))
         (face (if (equal (treesit-node-type
                           (treesit-node-prev-sibling semantics t))
                          "where_clause")
                   'font-lock-type-face
                 'font-lock-constant-face)))
    (treesit-fontify-with-override
     (treesit-node-start node) (treesit-node-end node)
     face override start end)))

(defvar slang-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'slang
   :feature 'comment
   `(((comment) @font-lock-doc-face
      (:match ,(rx bos "/**") @font-lock-doc-face))
     (comment) @font-lock-comment-face)

   :language 'slang
   :feature 'preprocessor
   `((preproc_directive) @font-lock-preprocessor-face

     (preproc_def
      name: (identifier) @font-lock-variable-name-face)

     (preproc_ifdef
      name: (identifier) @font-lock-variable-name-face)

     (preproc_elifdef
      name: (identifier) @font-lock-variable-name-face)

     (preproc_function_def
      name: (identifier) @font-lock-function-name-face)

     (preproc_params
      (identifier) @font-lock-variable-name-face)

     (preproc_defined
      "defined" @font-lock-preprocessor-face
      "(" @font-lock-preprocessor-face
      (identifier) @font-lock-variable-name-face
      ")" @font-lock-preprocessor-face)
     [,@slang-ts-mode--preproc-keywords] @font-lock-preprocessor-face)

   :language 'slang
   :feature 'attribute
   '((hlsl_attribute ["[" "]"] @font-lock-preprocessor-face)
     (hlsl_attribute (identifier) @font-lock-preprocessor-face)
     (hlsl_attribute
      (call_expression
       function: (identifier) @font-lock-preprocessor-face)))

   :language 'slang
   :feature 'constant
   '((true) @font-lock-constant-face
     (false) @font-lock-constant-face
     (null) @font-lock-constant-face
     (import_statement (identifier) @font-lock-constant-face))

   :language 'slang
   :feature 'semantics
   '((semantics (identifier) @slang-ts-mode--fontify-semantics)
     (field_declaration
      (bitfield_clause (identifier) @font-lock-constant-face)))

   :language 'slang
   :feature 'keyword
   `([,@slang-ts-mode--keywords] @font-lock-keyword-face
     (this) @font-lock-keyword-face)

   :language 'slang
   :feature 'operator
   `([,@slang-ts-mode--operators] @font-lock-operator-face
     "!" @font-lock-negation-char-face)

   :language 'slang
   :feature 'string
   '((string_literal) @font-lock-string-face
     (system_lib_string) @font-lock-string-face
     (raw_string_literal) @font-lock-string-face)

   :language 'slang
   :feature 'literal
   '((number_literal) @font-lock-number-face
     (char_literal) @font-lock-constant-face)

   :language 'slang
   :feature 'type
   `((primitive_type) @font-lock-type-face
     (type_identifier) @font-lock-type-face
     (sized_type_specifier) @font-lock-type-face
     (type_qualifier) @font-lock-type-face
     "This" @font-lock-type-face

     (qualified_identifier
      scope: (namespace_identifier) @font-lock-constant-face)

     (namespace_identifier) @font-lock-constant-face

     (interface_requirements (identifier) @font-lock-type-face)

     (binary_expression
      operator: ["is" "as"]
      right: (identifier) @font-lock-type-face)

     [,@slang-ts-mode--type-keywords] @font-lock-type-face)

   :language 'slang
   :feature 'definition
   '((declaration
      declarator: (_) @slang-ts-mode--fontify-declarator)

     (field_declaration
      declarator: (_) @slang-ts-mode--fontify-declarator)

     (function_definition
      declarator: (_) @slang-ts-mode--fontify-declarator)

     (parameter_declaration
      declarator: (_) @slang-ts-mode--fontify-declarator)

     (enumerator
      name: (identifier) @font-lock-property-name-face)

     (property_declaration
      (identifier) @font-lock-property-name-face)

     (expression_statement
      (identifier) @slang-ts-mode--fontify-toplevel-variable))

   :language 'slang
   :feature 'assignment
   '((assignment_expression
      left: (identifier) @font-lock-variable-name-face)
     (assignment_expression
      left: (field_expression field: (_) @font-lock-property-use-face))
     (assignment_expression
      left: (pointer_expression
             (identifier) @font-lock-variable-name-face))
     (assignment_expression
      left: (subscript_expression
             (identifier) @font-lock-variable-name-face))
     (init_declarator
      declarator: (_) @slang-ts-mode--fontify-declarator))

   :language 'slang
   :feature 'builtin
   `(((call_expression
       function: (identifier) @font-lock-builtin-face)
      (:match ,(rx-to-string
                `(seq bos (or ,@slang-ts-mode--intrinsic-functions) eos))
              @font-lock-builtin-face))
     ((call_expression
       function: (field_expression
                  field: (field_identifier) @font-lock-builtin-face))
      (:match ,(rx-to-string
                `(seq bos (or ,@slang-ts-mode--intrinsic-methods) eos))
              @font-lock-builtin-face)))

   :language 'slang
   :feature 'function
   '((call_expression
      function:
      [(identifier) @font-lock-function-call-face
       (field_expression
        field: (field_identifier) @font-lock-function-call-face)
       (template_function
        name: (identifier) @font-lock-function-call-face)
       (qualified_identifier
        name: (identifier) @font-lock-function-call-face)]))

   :language 'slang
   :feature 'variable
   '((identifier) @slang-ts-mode--fontify-variable)

   :language 'slang
   :feature 'label
   '((labeled_statement
      label: (statement_identifier) @font-lock-constant-face))

   :language 'slang
   :feature 'error
   '((ERROR) @font-lock-warning-face)

   :feature 'escape-sequence
   :language 'slang
   :override t
   '((escape_sequence) @font-lock-escape-face)

   :language 'slang
   :feature 'property
   '((field_identifier) @font-lock-property-use-face)

   :language 'slang
   :feature 'bracket
   '((["(" ")" "[" "]" "{" "}"]) @font-lock-bracket-face)

   :language 'slang
   :feature 'delimiter
   '((["," ":" ";" "::"]) @font-lock-delimiter-face))
  "Tree-sitter font-lock settings for `slang-ts-mode'.")

(defvar slang-ts-mode--feature-list
  '(( comment definition)
    ( keyword preprocessor string type)
    ( assignment attribute builtin constant escape-sequence
      label literal semantics)
    ( bracket delimiter error function operator property variable))
  "`treesit-font-lock-feature-list' for `slang-ts-mode'.")

(defun slang-ts-mode--defun-valid-p (node)
  "Return non-nil if NODE is a valid defun node.
Type specifiers must have a body (so mere type references don't
count), and variable declarations must be file- or
namespace-level and not function declarations."
  (pcase (treesit-node-type node)
    ((or "struct_specifier" "class_specifier" "union_specifier"
         "enum_specifier" "interface_specifier" "extension_specifier")
     (treesit-node-child-by-field-name node "body"))
    ("declaration"
     (and (not (equal (treesit-node-type
                       (treesit-node-child-by-field-name
                        node "declarator"))
                      "function_declarator"))
          (member (treesit-node-type (treesit-node-parent node))
                  '("translation_unit" "declaration_list"))))
    ("expression_statement"
     (slang-ts-mode--top-level-variable-p node))
    (_ t)))

(defun slang-ts-mode--defun-name (node)
  "Return the name of the defun NODE.
Return nil if NODE is not a defun node or doesn't have a name."
  (pcase (treesit-node-type node)
    ((or "function_definition" "declaration")
     (treesit-node-text
      (slang-ts-mode--declarator-identifier
       (treesit-node-child-by-field-name node "declarator")
       t)
      t))
    ((or "struct_specifier" "class_specifier" "union_specifier"
         "enum_specifier" "interface_specifier" "extension_specifier"
         "namespace_definition" "preproc_def" "preproc_function_def")
     (treesit-node-text
      (treesit-node-child-by-field-name node "name")
      t))
    ("associatedtype_declaration"
     (treesit-node-text (treesit-node-child node 0 t) t))
    ("property_declaration"
     (treesit-node-text
      (car (treesit-filter-child
            node
            (lambda (child)
              (equal (treesit-node-type child) "identifier"))))
      t))
    ("init_declaration" "__init")
    ("subscript_declaration" "__subscript")
    ("expression_statement"
     (treesit-node-text (treesit-node-child node 0 t) t))))

(defun slang-ts-mode--defun-skipper ()
  "Custom defun skipper for `slang-ts-mode'.
Struct definitions may end with a semicolon which is not part of
the struct node; skip it."
  (when (looking-at (rx (* (or " " "\t")) ";"))
    (goto-char (match-end 0)))
  (treesit-default-defun-skipper))

(defun slang-ts-mode--outline-predicate (node)
  "Match outline headings for NODE: functions and type definitions."
  (pcase (treesit-node-type node)
    ("function_declarator"
     (equal (treesit-node-type (treesit-node-parent node))
            "function_definition"))
    ((or "struct_specifier" "class_specifier" "union_specifier"
         "enum_specifier" "interface_specifier" "extension_specifier"
         "namespace_definition")
     (and (treesit-node-child-by-field-name node "body") t))
    (_ nil)))

(defvar slang-ts-mode--thing-settings
  `((sexp
     (not ,(rx (or "{" "}" "[" "]" "(" ")" ","))))
    (sentence
     ,(regexp-opt '("preproc"
                    "declaration"
                    "specifier"
                    "attributed_statement"
                    "labeled_statement"
                    "expression_statement"
                    "if_statement"
                    "switch_statement"
                    "do_statement"
                    "while_statement"
                    "for_statement"
                    "return_statement"
                    "break_statement"
                    "continue_statement"
                    "goto_statement"
                    "case_statement"
                    "discard_statement"
                    "import_statement")))
    (text
     ,(regexp-opt '("comment"
                    "raw_string_literal"))))
  "`treesit-thing-settings' for `slang-ts-mode'.")

;;;###autoload
(define-derived-mode slang-ts-mode prog-mode "Slang"
  "Major mode for editing Slang shader files, powered by tree-sitter.

This mode needs the tree-sitter grammar for Slang from
URL `https://github.com/theHamsta/tree-sitter-slang'.  You can
install it with \\[slang-ts-mode-install-grammar].

\\{slang-ts-mode-map}"
  :group 'slang-ts
  :syntax-table slang-ts-mode--syntax-table

  (when (treesit-ready-p 'slang)
    (treesit-parser-create 'slang)

    (setq-local syntax-propertize-function
                #'slang-ts-mode--syntax-propertize)

    (c-ts-common-comment-setup)

    (setq-local treesit-simple-indent-rules slang-ts-mode--indent-rules)
    (add-function :filter-args (local 'treesit-indent-function)
                  #'slang-ts-mode--before-indent)

    (setq-local electric-indent-chars
                (append "{}():;,#" electric-indent-chars))
    (setq-local indent-tabs-mode nil)

    (setq-local treesit-font-lock-settings slang-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list slang-ts-mode--feature-list)

    (setq-local treesit-defun-type-regexp
                (cons (rx bos
                          (or "function_definition"
                              "type_definition"
                              "struct_specifier"
                              "class_specifier"
                              "union_specifier"
                              "enum_specifier"
                              "interface_specifier"
                              "extension_specifier"
                              "namespace_definition"
                              "init_declaration"
                              "subscript_declaration"
                              "property_declaration"
                              "preproc_def"
                              "preproc_function_def")
                          eos)
                      #'slang-ts-mode--defun-valid-p))
    (setq-local treesit-defun-tactic 'top-level)
    (setq-local treesit-defun-skipper #'slang-ts-mode--defun-skipper)
    (setq-local treesit-defun-name-function #'slang-ts-mode--defun-name)
    (setq-local treesit-thing-settings
                `((slang ,@slang-ts-mode--thing-settings)))

    (setq-local treesit-simple-imenu-settings
                (let ((pred #'slang-ts-mode--defun-valid-p))
                  `(("Enum" ,(rx bos "enum_specifier" eos) ,pred nil)
                    ("Struct" ,(rx bos "struct_specifier" eos) ,pred nil)
                    ("Class" ,(rx bos "class_specifier" eos) ,pred nil)
                    ("Interface" ,(rx bos "interface_specifier" eos) ,pred nil)
                    ("Extension" ,(rx bos "extension_specifier" eos) ,pred nil)
                    ("Property" ,(rx bos "property_declaration" eos) nil nil)
                    ("Variable" ,(rx bos (or "declaration"
                                             "expression_statement")
                                     eos)
                     ,pred nil)
                    ("Function" ,(rx bos "function_definition" eos) nil nil))))

    (setq-local treesit-outline-predicate
                #'slang-ts-mode--outline-predicate)

    (treesit-major-mode-setup)))

(derived-mode-add-parents 'slang-ts-mode '(slang-mode))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.slangh?\\'" . slang-ts-mode))

(provide 'slang-ts-mode)

;;; slang-ts-mode.el ends here
