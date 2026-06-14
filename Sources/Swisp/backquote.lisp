;;; Backquote for Swisp — Lisp-based quasiquote expander
;;;
;;; Registers ` as a reader macro that expands quasiquote templates
;;; into cons/list/append/quote code at read time.

(define (unquote? x)
  (if (pair? x)
      (if (eq? (car x) 'unquote) (null? (cddr x)) #f)
      #f))

(define (unquote-splicing? x)
  (if (pair? x)
      (if (eq? (car x) 'unquote-splicing) (null? (cddr x)) #f)
      #f))

(define (bq-expand template)
  (if (unquote? template)
      (car (cdr template))
      (if (unquote-splicing? template)
          (car (cdr template))
          (if (not (pair? template))
              (list 'quote template)
              (bq-expand-list template)))))

(define (bq-expand-1 car-ex cdr-ex was-splicing)
  (if was-splicing
      (list 'append car-ex cdr-ex)
      (if (pair? cdr-ex)
          (if (eq? (car cdr-ex) 'quote)
              (if (null? (car (cdr cdr-ex)))
                  (list 'list car-ex)
                  (list 'cons car-ex cdr-ex))
              (list 'cons car-ex cdr-ex))
          (list 'cons car-ex cdr-ex))))

(define (bq-expand-list form)
  (if (null? form)
      '(quote ())
      (if (not (pair? form))
          (bq-expand form)
          (if (unquote? form)
              (bq-expand form)
              (if (unquote-splicing? form)
                  (error "backquote: ,@ in dot position")
                  (bq-expand-1 (bq-expand (car form))
                               (bq-expand-list (cdr form))
                               (unquote-splicing? (car form))))))))

(set-reader-macro-char "`" (lambda (c) (bq-expand (read))))

(provide 'backquote)
