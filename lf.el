;;; lf.el --- A Language Features library for Emacs Lisp  -*- lexical-binding: t; -*-

;; Copyright (c) 2021 Musa Al-hassy

;; Author: Musa Al-hassy <alhassy@gmail.com>
;; Version: 1.0
;; Package-Requires: ((s "1.12.0") (dash "2.16.0") (emacs "27.1"))
;; Keywords: convenience, programming
;; Repo: https://github.com/alhassy/lf.el
;; Homepage: https://alhassy.github.io/lf.el/

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

;; This library provides common desirable “L”anguage “F”eatures:
;;
;; 0. A unifed interface for defining both variables and functions.  LF-DEFINE.
;;
;; 1. A way to define typed, constrained, variables.  LF-DEFINE.
;;
;; 2. A way to define type specifed functions.  LF-DEFINE.
;;
;; 3. A macro to ease variable updates:  (lf-define very-long-name (f it))
;;                                     ≋ (setq very-long-name (f very-long-name))
;;
;; 4. A more verbose, yet friendlier, alternative to SETF: LF-DEFINE.
;;
;;
;; Minimal Working Example:
;;
;;     (lf-define age 0 [(integerp it) (<= 0 it 100)])
;;
;;     (lf-define age 123) ;; ⇒ Error: Existing constraints for “age” violated!
;;                         ;;  “age” is not updated; it retains old value.
;;
;;     (lf-define age 29)  ;; OK, “age” is now 29.
;;
;;
;; This file has been tangled from a literate, org-mode, file.
;;
;; There are numerous examples in tests.el.

;;; Code:

;; String and list manipulation libraries
;; https://github.com/magnars/dash.el
;; https://github.com/magnars/s.el

(require 's)               ;; “The long lost Emacs string manipulation library”
(require 'dash)            ;; “A modern list library for Emacs”
(require 'cl-lib)          ;; New Common Lisp library; ‘cl-???’ forms.

(defconst lf-version (package-get-version))
(defun lf-version ()
  "Print the current lf version in the minibuffer."
  (interactive)
  (message lf-version))

;;;###autoload
(define-minor-mode lf-mode
    "A Language Features library for Emacs Lisp"
  nil nil nil)

(cl-defun lf-documentation (name &optional kind newdoc)
  "Essentially, `lf-documentation' ≈ `documentation' + `documentation-property'.

If the final argument NEWDOC is provided, then this function becomes a setter;
otherwise it is a getter.

By default, Emacs Lisp's `documentation' returns the function documentation of
a given symbol.  As such, ours will be biased towards variable documentation.

\(lf-documentation NAME 'function)  ≈  (documentation NAME).

Interestingly, Common Lisp's `documentation' primitive takes
two arguments, NAME and KIND.  We have based ours on Common Lisp's."

  (setq kind (if (equal 'function kind) 'function-documentation 'variable-documentation))
  (if newdoc
      (put name kind newdoc)
    (documentation-property name kind)))

(cl-defmacro lf-undefine (&body symbols)
  "Ensure SYMBOLS are undefined, as variables and functions.

Zeros out variable's plists and deletes associated variable watchers.
Useful for testing."
  `(mapc (lambda (sym)
           (ignore-errors
             (makunbound sym)
             (setf (symbol-plist sym) nil) ;; Empty-out a var's plist.
             (--map (remove-variable-watcher sym it) (get-variable-watchers sym))
             (fmakunbound sym)))
         (quote ,symbols)))

(defun lf-extract-optionals-from-rest (vec str rest)
  "Provide a way to support &optional and &rest arguments of a particular shape.

For example, in `defun' one may provide an optional docstring;
likewise in `lf-define' one may provide a docstring but no vector
of constraints, or any other such mixture.  This metod ensures the
right variable refers to the right thing.

Return a list of length 3: The first being a vector or nil, the
second being a string or nil, and the last being a list.

VEC and STR are the values of &optional arguments that
are intended to be a vector and a string argument, respectively.
REST is the value of a &rest argument; i.e., a list."

  (cl-assert (listp rest))

  ; (when (equal '(nil) rest) (setq rest nil))
  (let ((result
  (cond
   ((and (not vec) (not str) (not rest)) (list nil nil nil))

   ;; Scenario: We have something as the first argument,
   ;; but it's not a vector nor a string: It's the start of the rest.
   ((and (not (vectorp vec)) (not (stringp vec)))
    (cond (str       (list nil nil (cons vec (cons str rest))))
          ((not str) (list nil nil (cons vec rest)))))

   ;; Scenario: We have not a vector, but a string as first argument.
   ((stringp vec) (cond (str (list nil vec (cons str rest)))
                        (:else (list nil vec rest))))

   ;; Scenario: We have a vector as the first argument...
   ((vectorp vec) (cond
                   ;; The second argument is a string...
                   ((stringp str) (list vec str rest))
                   ;; … followed by a non-string; i.e., the start of the rest
                   (:else (list vec nil (cons str rest))))))))

    ;; Assertions: result ≈ (vector? string? list)
    (cl-assert (or (vectorp (cl-first result)) (null (cl-first result))))
    (cl-assert (or (stringp (cl-second result)) (null (cl-second result))))
    (cl-assert (listp (cl-third result)))

    ;; Result value
    result))

(defmacro lf-define (place newvalue &optional constraints docstring &rest more)
"Essentially: `lf-define'  ≈  `setq' + `defvar' + `defun' + `setf'.

This is a unified variable/function definition interface, that
allows optional type CONSTRAINTS (in the shape of a vector)
followed by optional DOCSTRING.

It defines PLACE to be NEWVALUE, which satisfies CONSTRAINTS, as follows:

1. It can be used to define both variables and functions.

    (lf-define age 29 \"How old am I?\")

    (lf-define greet (name)
      \"Say hello to NAME\"
      (message-box \"Hello, %s!\" name))

    The documentation string for variables is optional, as with functions.
    The presence of MORE indicates that we are defining a function, with
    MORE serving as the function body.

2. It can be used to define *constrained* variables.  The
   following uses are equivalent; the first uses *type
   specifiers*, whereas the last uses an arbitrary predicate with
   the name ‘it’ referring to the name being defined.  By default,
   constraints are collected conjunctively.

      (lf-define age 0 [:type (integer 0 100)])
      ≈
      (lf-define age 0 [:type integer
                       (satisfies (lambda (value) (<= 0 value 100)))])
      ≈
      (lf-define age 0 [:type (and integer
                       (satisfies (lambda (value) (<= 0 value 100))))])
      ≈
      (lf-define age 0 [(integerp it) (<= 0 it 100)])

   Initial/new values not satifying the requested constraints
   result in an error.

      ;; Continuing with the above setup
      (lf-define age 123) ;; ⇒ Error: Existing constraints for “age” violated!

   If a constraint is declared and the initial value does not satisfy it, then
   the name being defined is made unbound, not defined at all.

      (lf-define age 0 [:type nil]) ;; Error; ‘age’ now unbound.

   If no constraint is declared, then the ‘lf-define’ is
   considered to be an update and so the most recent constraint
   is used to check the validity of the new value.
   Constraints are also checked whenever the variable is set with ‘setq’.

3. “Zap”: For non-function definitions, the expressions NEWVALUE may use the
   symbol IT, ‘it’, to refer to the variable name PLACE.

   As such:    (lf-define very-long-name (f it))
             ≈
               (setf very-long-name (f very-long-name))

   This also works when VERY-LONG-NAME is an arbitrary setffable place.

4. It can be used to define *constrained* functions.

    (lf-define speak (name age)
      [ :requires (stringp name) (integerp age)
        :ensures (stringp result)
      ]
      \"Produce an Arabic-English greeting.\"
      (format \"Marhaba! Hello %s-year old %s\" age name))

     (speak \"Yusuf\" 2) ;; ⇒ Marhaba! Hello 2-year old Yusuf
     (speak 'Yusuf  2)   ;; ⇒ Error: Constraints for “speak” have been violated!

   The use of ‘:requires’ is to explicitly provide machine-checked documentation
   of the expected inputs. Conversely, ‘:ensures’ communicates quickly to users
   the expected kind of output and it is machine-checked: Any future alterations
   to the function's implementation are checked to ensure the constraints are
   true.

5. If PLACE is a non-atomic form, then we default to using ‘setf’.

    (lf-define foods '(apple banana))
    (lf-define (car foods) 'pineapple)
    (cl-assert (equal foods '(pineapple banana)))"

  (cl-destructuring-bind (constraints docstring more)
      (lf-extract-optionals-from-rest constraints docstring more)

    (setq constraints (seq--into-list constraints))
    (cl-assert (or (listp constraints) (null constraints)))
    (cl-assert (or (stringp docstring)   (null docstring)))
    (cl-assert (listp more))

    (cond
     ;; (lf-define variable value [constraints] [documentation])
     ((and (atom place) (or (not more) (equal '(nil) more)))
      (lf--define-variable place newvalue constraints docstring))

     ;; (lf-define f (x) body)
     ((and (listp newvalue) more)
      (lf--define-function place newvalue constraints docstring more))

     ;; All else
     (t `(setf ,place  (let ((it ,place)) ,newvalue))))))

(defun lf--define-variable (name value constraints docstring)
  "Set variable NAME with VALUE satisfying CONSTRAINTS, with DOCSTRING.

The return value is (a piece of code that returns) the new value.
If there is no new constraints, then we perform an update; else
register the new constraints then perform the update.

NAME is an atomic symbol, VALUE is an arbitrary expression,
CONSTRAINTS is either a vector that begins with the keyword ‘:type’
followed by a sequence of type specifiers OR it is just a vector
of expressions ---namely, a Boolean valued expression that mentions
the name ‘it’, which refers to any new / initial values for NAME.

We assign the constraints under the symbols plist; this way it's
namespaced, and, more importantly, future lf-define's to the same
variable do not introduce new anyonmous watchers, but instead
redefine the one, and only, constraint LF maintains.
See: (get name :lf-constraints-func)"

  (when constraints
    (message "“%s” has new constraints registered: %s" name constraints)

    ;; Type specifier or not?
    (if (equal :type (elt constraints 0))
      (setq constraints `(cl-typep it (quote (and ,@(cdr constraints)))))
      (setq constraints (cons 'and constraints)))

    ;; Only continue if the value satisfies the constraints.  if initial
    ;; value does not satify constrains, leave name unbound.
    (unless (eval (cl-subst value 'it `,constraints))
      (ignore-errors (makunbound name))
      (error (concat "Error: Initial value “%s” violates declared constraint:"
                     "\n\t%s\n\nAs such, symbol “%s” is now unbound.")
                 value constraints name))

    ;; ADD-VARIABLE-WATCHER is idempotent; so no need to use REMOVE-VARIABLE-WATCHER.
    (setf (get name :lf-constraints-func)
          `(lambda (it.symbol it let-or-set _)
             "If we are doing a SET and the CONSTRAINTS fail, then error; else do nothing."
             (let ((it.old (and (boundp it.symbol) (symbol-value it.symbol))))
               (and (equal let-or-set 'set)
                    (not ,constraints)
                    (error (concat "Error: Constraints for “%s” "
                                   "have been violated.\nValue "
                                   "“%s” does not satisfy: %s")
                           it.symbol it (quote ,constraints))))))
    (add-variable-watcher name (get name :lf-constraints-func)))

  `(progn
     (setf (documentation-property (quote ,name) 'variable-documentation)
           (or ,docstring (documentation-property (quote ,name) 'variable-documentation)))
     (setf ,name ,(cl-subst name 'it value))))

(defun lf--define-function (name args constraints docstring body)
  "Define function NAME with type specification CONSTRAINTS.

The return value is (a piece of code that returns) the name of
the newly defiend function, as is the case with `defun'.

NAME is a symbol, ARGS is a list of symbols, DOCSTRING is a
string, BODY is an arbitrary form, and CONSTRAINTS is a vector
consisting of key-value pairs: The key ‘:requires’ and the key
‘:ensures’ are both Boolean valued expressions that may refer to
the symbols mentioned in ARGS.

Since the CONSTRAINTS can refer to arbitrary expressions
involving all of the variables, we have more than just simple
typing.  We have a form of specification."
  (let ((requires     (cl-getf constraints :requires t))
        (ensures      (cl-getf constraints :ensures  t))
        (advice-name  (intern (format "lf--typing-advice/%s" name))))
    `(progn
       (cl-defun ,name ,args ,docstring ,@body)

       (cl-defun ,advice-name (orig-fun &rest ,args)

         (unless ,requires
           (error "Error: Requirements for “%s” have been violated.\n\nREQUIRED:\n%s\nGIVEN:\n%s"
                  (quote ,name)
                  (pp-to-string (quote ,requires))
                  (pp-to-string (--map (list it '= (eval it) ': (type-of (eval it)))
                                       (quote ,args)))))

         (let ((result (funcall orig-fun ,@args)))
           (unless ,ensures
             (error (concat "Panic! There is an error in the implementation of “%s”."
                            "\n\nClaimed guarantee: %s\nActual result value: %s ---typed: %s")
                    (quote ,name)
                    (pp-to-string (quote ,ensures))
                    (pp-to-string result)
                    (type-of result)))

           result))

       (advice-add (function ,name) :around (quote ,advice-name))

       ;; Return value is the name of the newly defined function, as is the case with DEFUN
       (quote ,name))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(provide 'lf)

;;; lf.el ends here
