# slang-ts-mode

Tree-sitter major mode for the [Slang](https://shader-slang.org) shading
language. Requires Emacs 30.1+ with tree-sitter and the
[tree-sitter-slang](https://github.com/theHamsta/tree-sitter-slang) grammar.

## Setup

```elisp
(require 'slang-ts-mode)
;; First time only (needs git and a C compiler):
;; M-x slang-ts-mode-install-grammar
```

`.slang` and `.slangh` files then open in `slang-ts-mode`.

## Tests

```sh
emacs -Q -batch -L . -l test-slang-ts-mode.el -f ert-run-tests-batch-and-exit
```

## Acknowledgments

[K1ngst0m/slang-mode](https://github.com/K1ngst0m/slang-mode) was
referenced during development.
