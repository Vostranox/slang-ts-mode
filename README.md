# slang-ts-mode

Tree-sitter major mode for the [Slang](https://shader-slang.org) shading
language. Requires Emacs 30.1+ with tree-sitter and the
[tree-sitter-slang](https://github.com/theHamsta/tree-sitter-slang) grammar.

## Installation

From MELPA (pending):

```elisp
(use-package slang-ts-mode
  :ensure t)
```

Or manually, clone this repository and add it to your `load-path`:

```elisp
(add-to-list 'load-path "/path/to/slang-ts-mode")
(require 'slang-ts-mode)
```

`.slang` and `.slangh` files then open in `slang-ts-mode`.

## Tree-sitter grammar

The mode needs the
[tree-sitter-slang](https://github.com/theHamsta/tree-sitter-slang)
grammar. Building it requires git and a C compiler.

When the grammar is missing, the mode asks on first use whether to
download and build it. The variable `slang-ts-mode-grammar-install`
controls this: `ask` (the default), `always` to install without
asking, or `nil` to never install automatically. To install manually
instead, run `M-x slang-ts-mode-install-grammar`.

## Tests

```sh
emacs -Q -batch -L . -l test/slang-ts-mode-tests.el -f ert-run-tests-batch-and-exit
```

## Acknowledgments

[K1ngst0m/slang-mode](https://github.com/K1ngst0m/slang-mode) was
referenced during development.
