;;;; Copyright (c) 2017 Henry Harrington <henry.harrington@gmail.com>
;;;; This code is licensed under the MIT license.

(in-package :sys.c)

(defun apply-transforms (lambda target-architecture)
  (apply-transforms-1 lambda target-architecture))

(defgeneric apply-transforms-1 (form target-architecture))

(defmethod apply-transforms-1 ((form lexical-variable) target-architecture)
  form)

(defmethod apply-transforms-1 ((form lambda-information) target-architecture)
  (let ((*current-lambda* form))
    (dolist (arg (lambda-information-optional-args form))
      (setf (second arg) (apply-transforms-1 (second arg) target-architecture)))
    (dolist (arg (lambda-information-key-args form))
      (setf (second arg) (apply-transforms-1 (second arg) target-architecture)))
    (setf (lambda-information-body form)
          (apply-transforms-1 (lambda-information-body form) target-architecture)))
  form)

(defmethod apply-transforms-1 ((form ast-call) target-architecture)
 (let* ((matching-transform (match-transform form 't target-architecture))
        (new-form (if matching-transform
                      (apply-transform matching-transform (arguments form))
                      nil)))
   (cond (new-form
          (change-made)
          new-form)
         (t
          (setf (arguments form) (loop
                                    for arg in (arguments form)
                                    collect (apply-transforms-1 arg target-architecture)))
          form))))

(defmethod apply-transforms-1 ((form ast-block) target-architecture)
  (setf (body form) (apply-transforms-1 (body form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-function) target-architecture)
  (declare (ignore target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-go) target-architecture)
  (setf (info form) (apply-transforms-1 (info form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-if) target-architecture)
  (setf (test form) (apply-transforms-1 (test form) target-architecture)
        (if-then form) (apply-transforms-1 (if-then form) target-architecture)
        (if-else form) (apply-transforms-1 (if-else form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-let) target-architecture)
  (setf (bindings form) (loop
                           for (var initform) in (bindings form)
                           collect (list var (apply-transforms-1 initform target-architecture))))
  (setf (body form) (apply-transforms-1 (body form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-multiple-value-bind) target-architecture)
  (setf (value-form form) (apply-transforms-1 (value-form form) target-architecture)
        (body form) (apply-transforms-1 (body form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-multiple-value-call) target-architecture)
  (setf (function-form form) (apply-transforms-1 (function-form form) target-architecture)
        (value-form form) (apply-transforms-1 (value-form form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-multiple-value-prog1) target-architecture)
  (setf (value-form form) (apply-transforms-1 (value-form form) target-architecture)
        (body form) (apply-transforms-1 (body form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-progn) target-architecture)
  (setf (forms form) (loop
                        for subform in (forms form)
                        collect (apply-transforms-1 subform target-architecture)))
  form)

(defmethod apply-transforms-1 ((form ast-quote) target-architecture)
  (declare (ignore target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-return-from) target-architecture)
  (setf (value form) (apply-transforms-1 (value form) target-architecture)
        (info form) (apply-transforms-1 (info form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-setq) target-architecture)
  (setf (value form) (apply-transforms-1 (value form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-tagbody) target-architecture)
  (setf (statements form)
        (loop
           for (go-tag statement) in (statements form)
           collect (list go-tag (apply-transforms-1 statement target-architecture))))
  form)

(defmethod apply-transforms-1 ((form ast-the) target-architecture)
  (cond ((typep (value form) 'ast-call)
         (let* ((matching-transform (match-transform (value form) (the-type form) target-architecture))
                (new-form (if matching-transform
                              (apply-transform matching-transform (arguments (value form)))
                              nil)))
           (cond (new-form
                  (change-made)
                  (setf (value form) new-form))
                 (t
                  (setf (value form) (apply-transforms-1 (value form) target-architecture))))))
        (t
         (setf (value form) (apply-transforms-1 (value form) target-architecture))))
  form)

(defmethod apply-transforms-1 ((form ast-unwind-protect) target-architecture)
  (setf (protected-form form) (apply-transforms-1 (protected-form form) target-architecture))
  (setf (cleanup-function form) (apply-transforms-1 (cleanup-function form) target-architecture))
  form)

(defmethod apply-transforms-1 ((form ast-jump-table) target-architecture)
  (setf (value form) (apply-transforms-1 (value form) target-architecture))
  (setf (targets form) (kt-implicit-progn (targets form) target-architecture))
  form)

(defclass transform ()
  ((%function :initarg :function :reader transform-function)
   (%lambda-list :initarg :lambda-list :reader transform-lambda-list)
   (%argument-types :initarg :argument-types :reader transform-argument-types)
   (%result-type :initarg :result-type :reader transform-result-type)
   (%optimize :initarg :optimize :reader transform-optimize)
   (%architecture :initarg :architecture :reader transform-architecture)
   (%body :initarg :body :reader transform-body)
   (%documentation :initarg :documentation :reader transform-documentation))
  (:default-initargs
   :result-type 't
    :optimize '()
    :architecture 't
    :documentation nil))

(defmethod print-object ((object transform) stream)
  (print-unreadable-object (object stream :type t :identity t)
    (format stream "~S ~S -> ~S"
            (transform-function object)
            (mapcar #'list (transform-lambda-list object) (transform-argument-types object))
            (transform-result-type object))))

(defvar *transforms* '())

(defmacro define-transform (function lambda-list options &body body)
  (let ((lambda-parameters (loop
                              for l in lambda-list
                              collect (if (symbolp l)
                                          l
                                          (first l)))))
    `(register-transform (make-instance 'transform
                                        :function ',function
                                        :lambda-list ',lambda-parameters
                                        :argument-types ',(loop
                                                             for l in lambda-list
                                                             collect (if (symbolp l)
                                                                         't
                                                                         (or (second l) 't)))
                                        :body (lambda ,lambda-parameters
                                                (declare (ignorable ,@lambda-parameters))
                                                ,@body)
                                        ,@(loop for (option . rest) in options
                                             collect option
                                             collect (ecase option
                                                       (:documentation `',(first rest))
                                                       (:result-type `',(first rest))
                                                       (:optimize `',rest)
                                                       (:architecture `',rest)))))))

(defun register-transform (transform)
  (push transform *transforms*))

(defun match-optimize-settings (transform)
  (dolist (setting (transform-optimize transform)
           t)
    (when (not (funcall (first setting)
                        (if (integerp (second setting))
                            (second setting)
                            (optimize-quality *current-lambda* (second setting)))
                        (if (integerp (third setting))
                            (third setting)
                            (optimize-quality *current-lambda* (third setting)))))
      (return nil))))

(defun match-transform-type (transform-type type)
  (and (not (subtypep type 'nil))
       (subtypep type transform-type)))

(defun match-transform-argument (transform-type argument)
  (cond ((eql transform-type 't))
        ((typep argument 'ast-the)
         (match-transform-type transform-type (the-type argument)))
        ((typep argument 'ast-quote)
         (typep (value argument) transform-type))))

(defun match-transform (call result-type target-architecture)
  (dolist (transform *transforms* nil)
    (when (and (equal (transform-function transform) (ast-name call))
               (or (eql (transform-architecture transform) 't)
                   (member target-architecture (transform-architecture transform)))
               (match-optimize-settings transform)
               (match-transform-type (transform-result-type transform) result-type)
               (eql (length (arguments call)) (length (transform-lambda-list transform)))
               (every #'match-transform-argument
                      (transform-argument-types transform)
                      (arguments call)))
      (return transform))))

(defun apply-transform (transform arguments)
  (apply (transform-body transform) arguments))

;;; Unboxed fixnum arithmetic.
;;; These only apply at safety 0 as they can produce invalid values which
;;; can damage the system.

(defmacro define-fast-fixnum-transform-arith-two-arg (binary-fn fast-fn &key (result 'fixnum))
  `(define-transform ,binary-fn ((lhs fixnum) (rhs fixnum))
      ((:result-type ,result)
       (:optimize (= safety 0) (= speed 3)))
     (ast `(the fixnum (call ,',fast-fn ,lhs ,rhs)))))

(define-fast-fixnum-transform-arith-two-arg sys.int::binary-+ %fast-fixnum-+)
(define-fast-fixnum-transform-arith-two-arg sys.int::binary-- %fast-fixnum--)
(define-fast-fixnum-transform-arith-two-arg sys.int::binary-* %fast-fixnum-*)
(define-fast-fixnum-transform-arith-two-arg sys.int::%truncate %fast-fixnum-truncate)
(define-fast-fixnum-transform-arith-two-arg rem %fast-fixnum-rem)
(define-fast-fixnum-transform-arith-two-arg sys.int::binary-logior %fast-fixnum-logior :result t)
(define-fast-fixnum-transform-arith-two-arg sys.int::binary-logxor %fast-fixnum-logxor :result t)
(define-fast-fixnum-transform-arith-two-arg sys.int::binary-logand %fast-fixnum-logand :result t)
(define-fast-fixnum-transform-arith-two-arg mezzano.runtime::%fixnum-left-shift %fast-fixnum-left-shift)

;;; Fixnum comparisons.

(define-transform sys.int::binary-= ((lhs fixnum) (rhs fixnum))
    ((:optimize (= safety 0) (= speed 3)))
  (ast `(call eq ,lhs ,rhs)))

(define-transform sys.int::binary-< ((lhs fixnum) (rhs fixnum))
    ((:optimize (= safety 0) (= speed 3)))
  (ast `(call mezzano.runtime::%fixnum-< ,lhs ,rhs)))

(define-transform sys.int::binary->= ((lhs fixnum) (rhs fixnum))
    ((:optimize (= safety 0) (= speed 3)))
  (ast `(call not (call mezzano.runtime::%fixnum-< ,lhs ,rhs))))

(define-transform sys.int::binary-> ((lhs fixnum) (rhs fixnum))
    ((:optimize (= safety 0) (= speed 3)))
  (ast `(let ((lhs-value ,lhs)
              (rhs-value ,rhs))
          (call mezzano.runtime::%fixnum-< rhs-value lhs-value))))

(define-transform sys.int::binary-<= ((lhs fixnum) (rhs fixnum))
    ((:optimize (= safety 0) (= speed 3)))
  (ast `(let ((lhs-value ,lhs)
              (rhs-value ,rhs))
          (call not (call mezzano.runtime::%fixnum-< rhs-value lhs-value)))))

;;; Fast array accesses. Unbounded and may attack at any time.
;;; Currently only functional on simple 1d arrays.

(defmacro define-fast-array-transform (type accessor)
  `(progn
     (define-transform sys.int::aref-1 ((array (simple-array ,type (*))) index)
         ((:optimize (= safety 0) (= speed 3)))
       (ast `(the ,',type (call ,',accessor ,array ,index))))
     (define-transform (setf sys.int::aref-1) (value (array (simple-array ,type (*))) index)
         ((:optimize (= safety 0) (= speed 3)))
       (ast `(the ,',type (call (setf ,',accessor) ,value ,array ,index))))))

(define-fast-array-transform t sys.int::%object-ref-t)
(define-fast-array-transform fixnum sys.int::%object-ref-t)
(define-fast-array-transform (unsigned-byte 64) sys.int::%object-ref-unsigned-byte-64)
(define-fast-array-transform (unsigned-byte 32) sys.int::%object-ref-unsigned-byte-32)
(define-fast-array-transform (unsigned-byte 16) sys.int::%object-ref-unsigned-byte-16)
(define-fast-array-transform (unsigned-byte 8) sys.int::%object-ref-unsigned-byte-8)
(define-fast-array-transform (signed-byte 64) sys.int::%object-ref-signed-byte-64)
(define-fast-array-transform (signed-byte 32) sys.int::%object-ref-signed-byte-32)
(define-fast-array-transform (signed-byte 16) sys.int::%object-ref-signed-byte-16)
(define-fast-array-transform (signed-byte 8) sys.int::%object-ref-signed-byte-8)

(define-transform length ((sequence (and (simple-array * (*))
                                         (not (simple-array character (*))))))
    ((:optimize (= safety 0) (= speed 3)))
  (ast `(the (integer 0 ,array-dimension-limit) (call sys.int::%object-header-data ,sequence))))

;;; Misc transforms.

(defmacro define-type-predicate-transform (predicate type)
  `(progn
     (define-transform ,predicate ((object ,type))
         ((:optimize (= safety 0) (= speed 3)))
       (ast `'t))
     (define-transform ,predicate ((object (not ,type)))
         ((:optimize (= safety 0) (= speed 3)))
       (ast `'nil))))

(define-type-predicate-transform consp cons)
(define-type-predicate-transform vectorp vector)
(define-type-predicate-transform sys.int::fixnump fixnum)