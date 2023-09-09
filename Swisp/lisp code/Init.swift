let __init_lsp = """
;;;; Standard lisp functions
(setq *trace-level* 0)
(setq *log-level* 2)

(funset 'defspecial (nlambda (name params &rest body) (funset name (eval (cons 'nlambda (cons params body)))) name))
(defspecial defun (name params &rest body)
    (funset name (eval (cons 'lambda (cons params body))))
    (if (and (consp body)(stringp (car body))) (putprop name '*description* (car body)))
    name
)
(defspecial defmacro (name params &rest body) (funset name (eval (cons 'macro (cons params body)))) name)

(unclosure defun)  ;; hack, want them to be used in (flet (...) (defun ...)) and not bring their own closures
(unclosure defmacro)

(defmacro defparameter(var val)(list 'setq var val))
(defmacro defvar(var val)(list 'setq var val))
(defmacro defconst(var val)(list 'setq var val))

(defun null(x) (eq x nil))
(defun list (&rest l) l)
(defun not(x) (if x nil t))
;;(defmacro and(x y) (list 'if x y nil)) ;; built-in
;;(defmacro or(x y) (list 'if x x y))    ;; built-in

(defun equal(x y)
   (if (eq x y) t
       (if (and (consp x) (consp y))
           (and (equal (car x) (car y))
                   (equal (cdr x) (cdr y))))))


(defmacro when (test &rest body)
    (list 'if test (cons 'progn body)))

;;; (cond(test1 res1)(test2 res2)...) -> (if test1 res1 (if (test2 res2 ...)))

;(defmacro cond (&rest body)
;   (let* ((fc (fn (bl)
;                  (if (eq bl nil) nil
;                         (list 'if (car (car bl)) (cons 'progn (cdr (car bl)))
;                                  (fc (cdr bl)))))))
;       (fc body)))

(defun append(x y)
  (if (eq x '()) y
      (cons (car x)(append (cdr x) y))))

(defun reverse(x)
   (if (consp x)
      (append (reverse (cdr x))(list (car x)))
      x))

(defun memq (a l)
   (if (eq l nil) nil
       (if (eq a (car l)) l
           (memq a (cdr l)))))
 
(defvar *libraries* nil)

(defun provide (lib)
    (if (memq lib *libraries*) nil
        (setq *libraries* (cons lib *libraries*))))

(defun require (lib path)
    (if (memq lib *libraries*) nil
        (readfile path)))

;; Setup for backquote...
(defun assq (x y)
    (cond ((null y) nil)
        ((eq x (car (car y))) (car y))
        (t (assq x (cdr y))) ))

(defun putprop(props key val)
   (cond ((null props) (list (list key val)))
         ((eq (car (car props)) key) (cons (list key val) (cdr props)))
         (t (cons (car props) (putprop (cdr props) key val)))))
         
(defun nth (i l)
   (if (eq l nil) nil
       (if (eq i 0) (car l)
           (nth (- i 1) (cdr l)))))

(defun last (l)
    (if (null l) l
        (if (null (cdr l)) l
            (last (cdr l)))))
            
(defun nconc (&rest l)
    (if (null l) l
        (if (null (car l)) (nconc (cdr l))
            (if (null (cdr l)) (car l)
                (if (null (cdr (cdr l))) (progn (rplacd (last (car l)) (car (cdr l))) (car l))
                    (nconc (nconc (car l) (car (cdr l))) (cdr (cdr l))))))))

(defun vectorp (expr) nil)

(defmacro error (format &rest msgs)
   (list '*error* (cons 'strformat (cons format msgs))))

(readmacro "`" (lambda(stream) (list 'backquote (read stream))))
(readmacro "," (lambda(stream)
    (let ((c (peekchar stream)))
       (if (eq c ".")
           (progn (skipchar stream) (list '*back-comma-dot* (read stream)))
           (if (eq c "@") (progn (skipchar stream) (list '*back-comma-at* (read stream)))
                          (list '*back-comma* (read stream))))
    )
  )
)
(readmacro "#" (lambda(stream) (list 'function (read stream))))

(defun list* (&rest l)
    (let* ((fun (fn (x)
            (if (null x) x
               (if (null (cdr x)) (car x)
                  (cons (car x) (funcall fun (cdr x))))))))
     (funcall fun l)))

(require 'backquote "/backquote.lsp")

(defmacro unless (condition &rest body)
  `(if (not ,condition) (progn ,@body)))

(defmacro first(x)`(car ,x))
(defmacro rest(x)`(cdr ,x))
(defmacro second(x)`(car (cdr ,x)))
(defmacro third(x)`(car (cdr (cdr ,x))))
(defmacro caar(x)`(car (car ,x)))
(defmacro cadr(x)`(car (cdr ,x)))
(defmacro cdar(x)`(cdr (car ,x)))
(defmacro cddr(x)`(cdr (cdr ,x)))
(defmacro cdddr(x) `(cdr (cdr (cdr ,x))))
(defmacro cadar(x)`(car (cdr (car ,x))))

;;(defun apply(f arglist) `(funcall ,f ,(eval @arglist))) ;; builtin

(defmacro dolist(params &rest body)
    (let ((var (first params))(ll (gensym)))
    `(let ((,var nil)(,ll ,(second params)))
       (while ,ll
        (setq ,var (first ,ll))
        (setq ,ll (rest ,ll))
        ,@body))))

(defmacro dotimes(params &rest body)
    (let ((var (first params))(ll (gensym)))
    `(let ((,var 0)(,ll ,(second params)))
       (while (< ,var ,ll)
        (setq ,var (+ ,var 1))
        ,@body))))
    
(defmacro incf (var &optional (value 1))
    `(setq ,var (+ ,var ,value)))
    
(defmacro decf (var &optional (value 1))
    `(setq ,var (- ,var ,value)))
    
(defun map(f l)
  (let* ((fun (fn (l)
          (if l
              (cons (f (car l)) (funcall fun (cdr l)))))))
    (funcall fun l)))

(defun foldl(f e l)
  (let* ((fun (fn (l)
          (if l
              (f (car l) (fun(cdr l)))
            e))))
    (fun l)))
       
(defun add (&rest lst) (foldl + 0 lst))
(defun sub (a b) (- a b))
(defun mul (&rest lst) (foldl * 1 lst))
(defun div (a b) (/ a b))

;;; (case expr (val1 res1) (val2 res2) ...) -> (let ((test expr)) (cond ((eq test val1) res1) ...
(defmacro case (&rest body)
   (let* ((case1 (fn(x)
                       (if (null x) nil
                         (cons (cons (list 'eq '*temp* (caar x))
                                 (cdar x))
                           (case1 (cdr x)))))))
      (list 'let (list (list '*temp* (car body)))
             (cons 'cond (case1 (cdr body))))))
        
(defparameter *read-macros* nil)
(defun set-macro-character(c fun)
    (setq *read-macros* (putprop '*read-macros* c fun)))

;(set-macro-character 'foo ;#$
;   #'(lambda(stream char)
;      (list 'backquote (read stream t nil t))))

;;(defun verify() (readfile "lib/Lisp/verify.lsp"))

(defmacro time (expr)
  (let ((tt (gensym)) (res (gensym)))
    `(progn (setq ,tt (clock) ,res ,expr ,tt (- (clock) ,tt)) (format t "%s milliseconds\n" ,tt) ,res)))
    
(defun format (stream format &rest args)
    (print (unstr (apply #'strformat (cons format args)))))

(defvar * nil)
(defvar ** nil)
(defvar *** nil)

(defun toploop()
  (setq *trace-silent* T)
    (format t "Lisp>")
    (flush)
    (setq expr (read))
    (setq *trace-silent* NIL res (catch 'NIL (eval expr)))
    (setq *trace-silent* T)
    (when (not (memq expr '(* ** ***)))
        (setq *** **)
        (setq ** *)
        (setq * res))
    (format t "%s\n" res)
    (toploop)
)

(defun factrec(x) (if (eq x 0) 1 (* x (factrec (- x 1)))))
(flet ((factt(x acc) (if (eq x 0) acc (factt (- x 1) (* x acc)))))
   (defun fact(x) (factt x 1))
)

(defun filter(f x)
    (if (eq x nil) nil
        (if (#f (car x)) (cons (car x) (filter f (cdr x))) (filter f (cdr x)))) ;; #f => (function f)
)
(defun map(f x)
    (if (eq x nil) nil
        (cons (funcall f (car x)) (map f (cdr x))))
)
(defun mapf(f x)
    (if (eq x nil) nil
        (progn (funcall f (car x)) (mapf f (cdr x))))
)

(defun qsort (L)
  (cond
    ((null L) nil)
    (t
      (append
        (qsort (listLess (car L) (cdr L)))
        (cons (car L)
        (qsort (listGte (car L) (cdr L))))))))

(defun listLess (a b)
  (cond
    ((or (null a) (null b)) nil)
    ((< a (car b)) (listLess a (cdr b)))
    (t (cons (car b) (listLess a (cdr b))))))

(defun listGte (a b)
  (cond
    ((or (null a) (null b)) nil)
    ((>= a (car b)) (listGte a (cdr b)))
    (t (cons (car b) (listGte a (cdr b))))))

(defun list-funs()
    (mapf #'(lambda(f) (format t "fun:%s\n" f)) (filter #'function (qsort (symbol-table))))
)
"""

