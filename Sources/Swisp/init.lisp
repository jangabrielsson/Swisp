;;; Swisp standard library

;;; Basic predicates
(define (not x) (if x #f #t))
(define (zero? x) (= x 0))
(define (positive? x) (> x 0))
(define (negative? x) (< x 0))
(define (list? x) (if (null? x) #t (pair? x)))

;;; car/cdr compositions
(define (caar x) (car (car x)))
(define (cadr x) (car (cdr x)))
(define (cdar x) (cdr (car x)))
(define (cddr x) (cdr (cdr x)))
(define (caaar x) (car (car (car x))))
(define (caadr x) (car (car (cdr x))))
(define (cadar x) (car (cdr (car x))))
(define (caddr x) (car (cdr (cdr x))))
(define (cdaar x) (cdr (car (car x))))
(define (cdadr x) (cdr (car (cdr x))))
(define (cddar x) (cdr (cdr (car x))))
(define (cdddr x) (cdr (cdr (cdr x))))

;;; List accessor macros (inline car/cdr for speed)
(define-macro (first x) `(car ,x))
(define-macro (second x) `(cadr ,x))
(define-macro (third x) `(caddr ,x))
(define-macro (fourth x) `(cadddr ,x))
(define-macro (rest x) `(cdr ,x))

;;; List length
(define (length lst)
  (define (len n remaining)
    (if (null? remaining)
        n
        (len (+ n 1) (cdr remaining))))
  (len 0 lst))

;;; Reverse a list
(define (reverse lst)
  (define (rev acc remaining)
    (if (null? remaining)
        acc
        (rev (cons (car remaining) acc) (cdr remaining))))
  (rev '() lst))

;;; Append multiple lists
(define (append . lists)
  (define (append-two a b)
    (if (null? a)
        b
        (cons (car a) (append-two (cdr a) b))))
  (if (null? lists)
      '()
      (if (null? (cdr lists))
          (car lists)
          (append-two (car lists) (apply append (cdr lists))))))

;;; List-ref: access nth element of a list
(define (list-ref lst n)
  (if (= n 0)
      (car lst)
      (list-ref (cdr lst) (- n 1))))

;;; Member: find item in list, returns tail or #f
(define (member item lst)
  (if (null? lst)
      #f
      (if (equal? item (car lst))
          lst
          (member item (cdr lst)))))

;;; Assoc: lookup key in association list
(define (assoc key alist)
  (if (null? alist)
      #f
      (if (equal? key (caar alist))
          (car alist)
          (assoc key (cdr alist)))))

;;; Map: apply function to each element
(define (map f lst)
  (if (null? lst)
      '()
      (cons (f (car lst)) (map f (cdr lst)))))

;;; Filter: keep elements matching predicate
(define (filter pred lst)
  (if (null? lst)
      '()
      (if (pred (car lst))
          (cons (car lst) (filter pred (cdr lst)))
          (filter pred (cdr lst)))))

;;; For-each: apply function for side effects
(define (for-each f lst)
  (if (null? lst)
      '()
      (begin (f (car lst)) (for-each f (cdr lst)))))

;;; Load backquote reader macro
(require 'backquote)

(provide 'init)
