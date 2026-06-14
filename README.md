# Swisp

A Lisp interpreter written in Swift.

## Quick Start

```bash
swift run SwispCLI --repl          # Interactive REPL
swift run SwispCLI file.lisp       # Run a file
echo '(+ 1 2)' | swift run SwispCLI -  # Pipe stdin
```

## Features

- **BigInt arithmetic** — integers auto-promote to arbitrary precision on overflow
- **Reader macros** — register custom syntax via `(set-reader-macro-char char fn)`
- **Quasiquote** — `` `(a ,x ,@list) `` expanded by a Lisp reader macro
- **Rest parameters** — `(lambda (a b . rest) ...)`
- **`apply` / `funcall`** — spread lists into function calls
- **`setq`** — multiple-pair assignment
- **`require` / `provide`** — load Lisp libraries
- **CPS evaluator** — continuation-passing style with trampoline
- **Clean errors** — no Swift stack traces for Lisp errors
- **REPL** — with multi-line expression support

## Examples

```lisp
;; BigInt — no overflow
(fact 100)

;; Rest params
(define (sum . nums) (apply + nums))

;; Reader macro for lambda
(set-reader-macro-char "!" (lambda (c) (list 'lambda (read) (read))))
(map !(x) (* x x) '(1 2 3))  ; → (1 4 9)

;; Quasiquote
`(a ,@(map (lambda (n) (* n n)) '(1 2 3)))
```

## Builtins

Arithmetic: `+` `-` `*` `/`  
Comparison: `=` `<` `>` `<=` `>=`  
Lists: `cons` `car` `cdr` `list` `null?` `eq?` `equal?`  
Predicates: `number?` `symbol?` `string?` `boolean?` `pair?`  
Functions: `apply` `funcall`  
I/O: `print` `display` `newline` `read` `read-char` `peek-char`  
Reader: `set-reader-macro-char`  
System: `error` `require` `provide`  

Special forms: `quote` `if` `lambda` `define` `define-macro` `set!` `setq` `begin` `quasiquote` `require`

## License

MIT
