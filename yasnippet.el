;;; yasnippet.el --- Yet another snippet extension for Emacs.

;; Copyright 2008 pluskid
;;
;; Author: pluskid <pluskid@gmail.com>
;; Version: 0.5.6 XXX: Change this
;; X-URL: http://code.google.com/p/yasnippet/

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; Basic steps to setup:
;;   1. Place `yasnippet.el' in your `load-path'.
;;   2. In your .emacs file:
;;        (require 'yasnippet)
;;   3. Place the `snippets' directory somewhere.  E.g: ~/.emacs.d/snippets
;;   4. In your .emacs file
;;        (yas/initialize)
;;        (yas/load-directory "~/.emacs.d/snippets")
;;
;; For more information and detailed usage, refer to the project page:
;;      http://code.google.com/p/yasnippet/

(require 'cl)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; User customizable variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar yas/dont-activate nil
  "If set to t, don't activate yas/minor-mode automatically.")
(make-variable-buffer-local 'yas/dont-activate)

(defvar yas/key-syntaxes (list "w" "w_" "w_." "^ ")
  "A list of syntax of a key. This list is tried in the order
to try to find a key. For example, if the list is '(\"w\" \"w_\").
And in emacs-lisp-mode, where \"-\" has the syntax of \"_\":

foo-bar

will first try \"bar\", if not found, then \"foo-bar\" is tried.")

(defvar yas/root-directory nil
  "The (list of) root directory that stores the snippets for each
major modes.")

(defvar yas/indent-line t
  "Each (except the 1st) line of the snippet template is indented to
current column if this variable is non-`nil'.")
(make-variable-buffer-local 'yas/indent-line)

(defvar yas/trigger-key (kbd "<tab>")
  "The key to bind as a trigger of snippet.")
(defvar yas/next-field-key (kbd "<tab>")
  "The key to navigate to next field.")
(defvar yas/clear-field-key (kbd "C-d")
  "The key to clear the currently active field.")

(defvar yas/keymap (make-sparse-keymap)
  "The keymap of snippet.")
(define-key yas/keymap yas/next-field-key 'yas/next-field)
(define-key yas/keymap yas/clear-field-key 'yas/clear-field-or-delete-char)
(define-key yas/keymap (kbd "S-TAB") 'yas/prev-field)
(define-key yas/keymap (kbd "<deletechar>") 'yas/prev-field)
(define-key yas/keymap (kbd "<S-iso-lefttab>") 'yas/prev-field)
(define-key yas/keymap (kbd "<S-tab>") 'yas/prev-field)
(define-key yas/keymap (kbd "<backtab>") 'yas/prev-field)

(defvar yas/show-all-modes-in-menu nil
  "Currently yasnippet only all \"real modes\" to menubar. For
example, you define snippets for \"cc-mode\" and make it the
parent of `c-mode', `c++-mode' and `java-mode'. There's really
no such mode like \"cc-mode\". So we don't show it in the yasnippet
menu to avoid the menu becoming too big with strange modes. The
snippets defined for \"cc-mode\" can still be accessed from
menu-bar->c-mode->parent (or c++-mode, java-mode, all are ok).
However, if you really like to show all modes in the menu, set
this variable to t.")
(defvar yas/use-menu t
  "If this is set to `t', all snippet template of the current
mode will be listed under the menu \"yasnippet\".")
(defvar yas/trigger-symbol " =>"
  "The text that will be used in menu to represent the trigger.")

(defface yas/field-highlight-face
  '((((class color) (background light)) (:background "DarkSeaGreen1"))
    (t (:background "DimGrey")))
  "The face used to highlight the currently active field of a snippet")

(defface yas/mirror-highlight-face
  '((((class color) (background light)) (:background "Dodgerblue"))
    (t (:background "DimGrey")))
  "The face used to highlight a mirror of a snippet")

(defface yas/field-debug-face
  '((((class color) (background light)) (:background "tomato"))
    (t (:background "tomato")))
  "The face used for debugging")

(defvar yas/window-system-popup-function #'yas/dropdown-list-popup-for-template
  "When there's multiple candidate for a snippet key. This function
is called to let user select one of them. `yas/text-popup-function'
is used instead when not in a window system.")
(defvar yas/text-popup-function #'yas/dropdown-list-popup-for-template
  "When there's multiple candidate for a snippet key. If not in a
window system, this function is called to let user select one of
them. `yas/window-system-popup-function' is used instead when in
a window system.")

(defvar yas/extra-mode-hooks
  '()
  "A list of mode-hook that should be hooked to enable yas/minor-mode.
Most modes need no special consideration.  Some mode (like `ruby-mode')
doesn't call `after-change-major-mode-hook' need to be hooked explicitly.")
(mapc '(lambda (x)
         (add-to-list 'yas/extra-mode-hooks
                      x))
      '(ruby-mode-hook actionscript-mode-hook ox-mode-hook python-mode-hook))

(defvar yas/after-exit-snippet-hook
  '()
  "Hooks to run after a snippet exited.
The hooks will be run in an environment where some variables bound to
proper values:
 * yas/snippet-beg : The beginning of the region of the snippet.
 * yas/snippet-end : Similar to beg.")

(defvar yas/before-expand-snippet-hook
  '()
  "Hooks to run after a before expanding a snippet.")

(defvar yas/buffer-local-condition
  '(if (and (not (bobp))
            (or (equal "font-lock-comment-face"
                       (get-char-property (1- (point))
                                          'face))
                (equal "font-lock-string-face"
                       (get-char-property (1- (point))
                                          'face))))
       '(require-snippet-condition . force-in-comment)
     t)
  "Condition to yasnippet local to each buffer.

    * If yas/buffer-local-condition evaluate to nil, snippet
      won't be expanded.

    * If it evaluate to the a cons cell where the car is the
      symbol require-snippet-condition and the cdr is a
      symbol (let's call it requirement):
       * If the snippet has no condition, then it won't be
         expanded.
       * If the snippet has a condition but evaluate to nil or
         error occured during evaluation, it won't be expanded.
       * If the snippet has a condition that evaluate to
         non-nil (let's call it result):
          * If requirement is t, the snippet is ready to be
            expanded.
          * If requirement is eq to result, the snippet is ready
            to be expanded.
          * Otherwise the snippet won't be expanded.
    * If it evaluate to other non-nil value:
       * If the snippet has no condition, or has a condition that
         evaluate to non-nil, it is ready to be expanded.
       * Otherwise, it won't be expanded.

Here's an example:

 (add-hook 'python-mode-hook
           '(lambda ()
              (setq yas/buffer-local-condition
                    '(if (python-in-string/comment)
                         '(require-snippet-condition . force-in-comment)
                       t))))")

(defvar yas/fallback-behavior 'call-other-command
  "The fall back behavior of YASnippet when it can't find a snippet
to expand.

 * 'call-other-command means try to temporarily disable
    YASnippet and call other command bound to `yas/trigger-key'.
 * 'return-nil means return nil.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Internal variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar yas/version "0.5.6-nested-placeholders")

(defvar yas/snippet-tables (make-hash-table)
  "A hash table of snippet tables corresponding to each major-mode.")
(defvar yas/menu-table (make-hash-table)
  "A hash table of menus of corresponding major-mode.")
(defvar yas/menu-keymap (make-sparse-keymap "YASnippet"))
;; empty menu will cause problems, so we insert some items
(define-key yas/menu-keymap [yas/about]
  '(menu-item "About" yas/about))
(define-key yas/menu-keymap [yas/reload]
  '(menu-item "Reload all snippets" yas/reload-all))
(define-key yas/menu-keymap [yas/load]
  '(menu-item "Load snippets..." yas/load-directory))
(define-key yas/menu-keymap [yas/separator]
  '(menu-item "--"))

(defvar yas/known-modes
  '(ruby-mode rst-mode markdown-mode)
  "A list of mode which is well known but not part of emacs.")
(defconst yas/escape-backslash
  (concat "YASESCAPE" "BACKSLASH" "PROTECTGUARD"))
(defconst yas/escape-dollar
  (concat "YASESCAPE" "DOLLAR" "PROTECTGUARD"))
(defconst yas/escape-backquote
  (concat "YASESCAPE" "BACKQUOTE" "PROTECTGUARD"))

(defconst yas/field-regexp
  "${\\([0-9]+:\\)?\\([^}]*\\)}"
  "A regexp to *almost* recognize a field")

(defconst yas/transform-mirror-regexp
  "${\\(?:\\([0-9]+\\):\\)?$\\([^}]*\\)"
  "A regexp to *almost* recognize a mirror with a transform")

(defconst yas/simple-mirror-regexp
  "$\\([0-9]+\\)"
  "A regexp to recognize a simple mirror")

(defvar yas/snippet-id-seed 0
  "Contains the next id for a snippet.")
(defun yas/snippet-next-id ()
  (let ((id yas/snippet-id-seed))
    (incf yas/snippet-id-seed)
    id))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; YASnippet minor mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar yas/minor-mode-map (make-sparse-keymap)
  "The keymap of yas/minor-mode")
(defvar yas/minor-mode-on-hook nil
  "Hook to call when yas/minor-mode is on.")
(defvar yas/minor-mode-off-hook nil
  "Hook to call when yas/minor-mode is off.")
(define-minor-mode yas/minor-mode
  "Toggle YASnippet mode.
With no argument, this command toggles the mode.
positive prefix argument turns on the mode.
Negative prefix argument turns off the mode.

When YASnippet mode is enabled, the TAB key
expands snippets of code depending on the mode.

You can customize the key through `yas/trigger-key'."
  ;; The initial value.
  nil
  ;; The indicator for the mode line.
  " yas"
  :group 'editing
  (define-key yas/minor-mode-map yas/trigger-key 'yas/expand)
  (if yas/minor-mode
      (progn
	(add-hook 'post-command-hook 'yas/post-command-handler nil t)
	(add-hook 'pre-command-hook 'yas/pre-command-handler t t))
    (remove-hook 'post-command-hook 'yas/post-command-handler)
    (remove-hook 'pre-command-hook 'yas/pre-command-handler)))

(defun yas/minor-mode-auto-on ()
  "Turn on YASnippet minor mode unless `yas/dont-activate' is
set to t."
  (unless yas/dont-activate
    (yas/minor-mode-on)))
(defun yas/minor-mode-on ()
  "Turn on YASnippet minor mode."
  (interactive)
  (yas/minor-mode 1))
(defun yas/minor-mode-off ()
  "Turn off YASnippet minor mode."
  (interactive)
  (yas/minor-mode -1))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Internal Structs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defstruct (yas/template (:constructor yas/make-template
                                       (content name condition)))
  "A template for a snippet."
  content
  name
  condition)

(defvar yas/active-field-overlay nil
  "Overlays the currently active field")

(defvar yas/field-protection-overlays nil
  "Two overlays protect the current active field ")

(make-variable-buffer-local 'yas/active-field-overlay)
(make-variable-buffer-local 'yas/field-protection-overlays)

(defstruct (yas/snippet (:constructor yas/make-snippet ()))
  "A snippet.

..."
  (fields '())
  (exit nil)
  (id (yas/snippet-next-id) :read-only t)
  (control-overlay nil)
  active-field)

(defstruct (yas/field (:constructor yas/make-field (number start end parent-field)))
  "A field."
  number
  start end
  parent-field
  (mirrors '())
  (next nil)
  (prev nil)
  (transform nil)
  (modified-p nil))

(defstruct (yas/mirror (:constructor yas/make-mirror (start end transform)))
  "A mirror."
  start end
  (transform nil))

(defstruct (yas/snippet-table (:constructor yas/make-snippet-table ()))
  "A table to store snippets for a perticular mode."
  (hash (make-hash-table :test 'equal))
  (parent nil))

(defun yas/snippet-find-field (snippet number) 
  (find-if #'(lambda (field)
	       (eq number (yas/field-number field)))
	   (yas/snippet-fields snippet)))

(defun yas/snippet-field-compare (field1 field2)
  "Compare two fields. The field with a number is sorted first.
If they both have a number, compare through the number. If neither
have, compare through the field's start point"
  (let ((n1 (yas/field-number field1))
        (n2 (yas/field-number field2)))
    (if n1
        (if n2
            (< n1 n2)
          t)
      (if n2
          nil
        (< (yas/field-start field1)
           (yas/field-start field2))))))

(defun yas/template-condition-predicate (condition)
  (condition-case err
      (save-excursion
        (save-restriction
          (save-match-data
            (eval condition))))
    (error (progn
             (message (format "[yas]error in condition evaluation: %s"
                              (error-message-string err)))
             nil))))

(defun yas/filter-templates-by-condition (templates)
  "Filter the templates using the condition. The rules are:

 * If the template has no condition, it is kept.
 * If the template's condition eval to non-nil, it is kept.
 * Otherwise (eval error or eval to nil) it is filtered."
  (remove-if-not '(lambda (pair)
                    (let ((condition (yas/template-condition (cdr pair))))
                      (if (null condition)
                          (if yas/require-template-condition
                              nil
                            t)
                        (let ((result
                               (yas/template-condition-predicate condition)))
                          (if yas/require-template-condition
                              (if (eq yas/require-template-condition t)
                                  result
                                (eq result yas/require-template-condition))
                            result)))))
                 templates))

(defun yas/snippet-table-fetch (table key)
  "Fetch a snippet binding to KEY from TABLE. If not found,
fetch from parent if any."
  (let ((templates (yas/filter-templates-by-condition
                    (gethash key (yas/snippet-table-hash table)))))
    (when (and (null templates)
               (not (null (yas/snippet-table-parent table))))
      (setq templates (yas/snippet-table-fetch
                       (yas/snippet-table-parent table)
                       key)))
    templates))
(defun yas/snippet-table-store (table full-key key template)
  "Store a snippet template in the table."
  (puthash key
           (yas/modify-alist (gethash key
                                      (yas/snippet-table-hash table))
                             full-key
                             template)
           (yas/snippet-table-hash table)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Internal functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun yas/ensure-minor-mode-priority ()
  "Ensure that the key binding of yas/minor-mode takes priority."
  (unless (eq 'yas/minor-mode
              (caar minor-mode-map-alist))
    (setq minor-mode-map-alist
          (cons
           (cons 'yas/minor-mode yas/minor-mode-map)
           (assq-delete-all 'yas/minor-mode
                            minor-mode-map-alist)))))

(defun yas/real-mode? (mode)
  "Try to find out if MODE is a real mode. The MODE bound to
a function (like `c-mode') is considered real mode. Other well
known mode like `ruby-mode' which is not part of Emacs might
not bound to a function until it is loaded. So yasnippet keeps
a list of modes like this to help the judgement."
  (or (fboundp mode)
      (find mode yas/known-modes)))

(defun yas/eval-string (string)
  "Evaluate STRING and convert the result to string."
  (condition-case err
      (save-excursion
        (save-restriction
          (save-match-data
            (widen)
            (format "%s" (eval (read string))))))
    (error (format "(error in elisp evaluation: %s)"
                   (error-message-string err)))))

(defun yas/apply-transform (field-or-mirror field)
  "Calculate the value of the field. If there's a transform
for this field, apply it. Otherwise, the value is returned
unmodified.

TODO: I really dont think field transforms are easily done, but oh
well

"
  (let ((text (yas/field-text-for-display field))
        (transform (if (yas/mirror-p field-or-mirror)  
		       (yas/mirror-transform field-or-mirror)
		     (yas/field-transform field-or-mirror))))
    (if transform
        (yas/eval-string transform)
      text)))

(defsubst yas/replace-all (from to)
  "Replace all occurance from FROM to TO."
  (goto-char (point-min))
  (while (search-forward from nil t)
    (replace-match to t t)))

(defun yas/snippet-table (mode)
  "Get the snippet table corresponding to MODE."
  (let ((table (gethash mode yas/snippet-tables)))
    (unless table
      (setq table (yas/make-snippet-table))
      (puthash mode table yas/snippet-tables))
    table))
(defsubst yas/current-snippet-table ()
  "Get the snippet table for current major-mode."
  (yas/snippet-table major-mode))

(defun yas/menu-keymap-for-mode (mode)
  "Get the menu keymap correspondong to MODE."
  (let ((keymap (gethash mode yas/menu-table)))
    (unless keymap
      (setq keymap (make-sparse-keymap))
      (puthash mode keymap yas/menu-table))
    keymap))

(defun yas/current-key ()
  "Get the key under current position. A key is used to find
the template of a snippet in the current snippet-table."
  (let ((start (point))
        (end (point))
        (syntaxes yas/key-syntaxes)
        syntax done templates)
    (while (and (not done) syntaxes)
      (setq syntax (car syntaxes))
      (setq syntaxes (cdr syntaxes))
      (save-excursion
        (skip-syntax-backward syntax)
        (setq start (point)))
      (setq templates
            (yas/snippet-table-fetch
             (yas/current-snippet-table)
             (buffer-substring-no-properties start end)))
      (if templates
          (setq done t)
        (setq start end)))
    (list templates
          start
          end)))

(defun yas/field-text-for-display (field)
  "Return the propertized display text for field FIELD.  "
  (buffer-substring (yas/field-start field) (yas/field-end field)))

(defun yas/undo-in-progress ()
  (or undo-in-progress
      (eq this-command 'undo))) 

(defun yas/make-control-overlay (start end)
  "..."
  (let ((overlay (make-overlay start
                               end
                               nil
                               t 
                               t)))
    (overlay-put overlay 'keymap yas/keymap)
    (overlay-put overlay 'yas/snippet snippet)
    (overlay-put overlay 'evaporate t)
    overlay))

(defun yas/clear-field-or-delete-char (&optional field)
  (interactive)
  (let ((field (or field
		   (and yas/active-field-overlay
			(overlay-buffer yas/active-field-overlay)
			(overlay-get yas/active-field-overlay 'yas/field)))))
    (cond ((and field
		(not (yas/field-modified-p field)))
	   (yas/clear-field field))
	  (t
	   (call-interactively 'delete-char)))))

(defun yas/clear-field (field)
  (setf (yas/field-modified-p field) t)
  (delete-region (yas/field-start field) (yas/field-end field)))

(defun yas/on-field-overlay-modification (overlay after? beg end &optional length)
  "Clears the field and updates mirrors, conditionally.

Only clears the field if it hasn't been modified and it point it
at field start. This hook doesn't do anything if an undo is in
progress."
  (unless (yas/undo-in-progress)
    (cond (after?
	   (mapcar #'yas/update-mirrors (yas/snippets-at-point)))
	  (t
	   (let ((field (overlay-get yas/active-field-overlay 'yas/field)))
	     (when (and field
			(not after?)
			(not (yas/field-modified-p field))
			(eq (point) (if (markerp (yas/field-start field))
					(marker-position (yas/field-start field))
				      (yas/field-start field))))
	       (yas/clear-field field))
	     (setf (yas/field-modified-p field) t))))))

(defun yas/on-protection-overlay-modification (overlay after? beg end &optional length)
  "To be written"
  (cond ((not (or after?
		  (yas/undo-in-progress)))
	 (let ((snippet (car (yas/snippets-at-point))))
	   (when snippet
	     (yas/commit-snippet snippet)
	     (call-interactively this-command)
	     (error "Snippet exited"))))))

(defun yas/expand-snippet (start end template)
  "Expand snippet at current point. Text between START and END
will be deleted before inserting template."
  (run-hooks 'yas/before-expand-snippet-hook)
  (goto-char start)

  (let* ((key (buffer-substring-no-properties start end))
	 (length (- end start))
	 (column (current-column))
	 (inhibit-modification-hooks t)
	 snippet)
    (delete-char length)
    (save-restriction
      (let ((buffer-undo-list t))
	(narrow-to-region start start)
	(insert template)
	(setq snippet (yas/snippet-create (point-min) (point-max))))
      (push (cons (point-min) (point-max)) buffer-undo-list)
      ;; Push an undo action
      (push `(apply yas/take-care-of-redo ,(point-min) ,(point-max) ,snippet)
	    buffer-undo-list))


    ;; if this is a stacked expansion update the other snippets at point
    (mapcar #'yas/update-mirrors (rest (yas/snippets-at-point)))))

(defun yas/take-care-of-redo (beg end snippet)
  (yas/commit-snippet snippet))

(defun yas/snippet-revive (beg end snippet)
  (setf (yas/snippet-control-overlay snippet) (yas/make-control-overlay beg end))
  (overlay-put (yas/snippet-control-overlay snippet) 'yas/snippet snippet)
  (yas/move-to-field snippet (or (yas/snippet-active-field snippet)
				 (car (yas/snippet-fields snippet))))
  (yas/points-to-markers snippet)
  (push `(apply yas/take-care-of-redo ,beg ,end ,snippet)
	buffer-undo-list))

(defun yas/snippet-create (begin end)
  (let ((snippet (yas/make-snippet)))
    (goto-char begin)
    (yas/snippet-parse-create snippet)

    ;; Sort and link each field
    (yas/snippet-sort-link-fields snippet)
    
    ;; Update the mirrors for the first time
    (yas/update-mirrors snippet)

    ;; Create keymap overlay for snippet
    (setf (yas/snippet-control-overlay snippet) (yas/make-control-overlay (point-min) (point-max)))

    ;; Move to end
    (goto-char (point-max))

    ;; Place the cursor at a proper place
    (let* ((first-field (car (yas/snippet-fields snippet)))
	   overlay)
      (cond (first-field
	     ;; Move to the new field, setting up properties of the
	     ;; wandering active field overlay.
	     (yas/move-to-field snippet first-field))
	    (t
	     ;; No fields, quite a simple snippet I suppose
	     (yas/exit-snippet snippet))))
    snippet))

(defun yas/snippet-sort-link-fields (snippet)
  (setf (yas/snippet-fields snippet)
	(sort (yas/snippet-fields snippet)
	      '(lambda (field1 field2)
		 (yas/snippet-field-compare field1 field2))))
  (let ((prev nil))
    (dolist (field (yas/snippet-fields snippet))
      (setf (yas/field-prev field) prev)
      (when prev
	(setf (yas/field-next prev) field))
      (setq prev field))))

(defun yas/snippet-parse-create (snippet)
  "Parse a recently inserted snippet template, creating all
necessary fields.

Allows nested placeholder in the style of Textmate."
  (let ((parse-start (point)))
    (yas/field-parse-create snippet)
    (goto-char parse-start)
    (yas/transform-mirror-parse-create snippet)
    (goto-char parse-start)
    (yas/simple-mirror-parse-create snippet)))

(defun yas/field-parse-create (snippet &optional parent-field)
    (while (re-search-forward yas/field-regexp nil t)
      (let* ((real-match-end-0 (scan-sexps (1+ (match-beginning 0)) 1))
	     (number (string-to-number (match-string-no-properties 1)))
	     (brand-new-field (and real-match-end-0
				   (save-match-data (not (string-match "$(" (match-string-no-properties 2)))) 
				   number
				   (not (zerop number))
				   (yas/make-field number
						   (set-marker (make-marker) (match-beginning 2))
						   (set-marker (make-marker) (1- real-match-end-0))
						   parent-field))))
	(when brand-new-field
	  (delete-region (1- real-match-end-0) real-match-end-0)
	  (delete-region (match-beginning 0) (match-beginning 2))
	  (push brand-new-field (yas/snippet-fields snippet))
	  (save-excursion
	    (save-restriction
	      (narrow-to-region (yas/field-start brand-new-field) (yas/field-end brand-new-field))
	      (goto-char (point-min))
	      (yas/field-parse-create snippet brand-new-field)))))))

(defun yas/transform-mirror-parse-create (snippet)
  (while (re-search-forward yas/transform-mirror-regexp nil t)
    (let* ((real-match-end-0 (scan-sexps (1+ (match-beginning 0)) 1))
	  (number (string-to-number (match-string-no-properties 1)))
	  (field (and number
		      (not (zerop number))
		      (yas/snippet-find-field snippet number))))
      (when (and real-match-end-0 field) 
	(push (yas/make-mirror (set-marker (make-marker) (match-beginning 0))
			       (set-marker (make-marker) (match-beginning 0))
			       (buffer-substring-no-properties (match-beginning 2)
							       (1- real-match-end-0)))
	      (yas/field-mirrors field))
	(delete-region (match-beginning 0) real-match-end-0)))))

(defun yas/simple-mirror-parse-create (snippet)
  (while (re-search-forward yas/simple-mirror-regexp nil t)
    (let ((number (string-to-number (match-string-no-properties 1))))
      (cond ((zerop number)
	     (setf (yas/snippet-exit snippet)
		(set-marker (make-marker) (match-beginning 0)))
	     (delete-region (match-beginning 0) (match-end 0)))
	    (t
	     (let ((field (yas/snippet-find-field snippet number)))
	       (when field
		 (push (yas/make-mirror (set-marker (make-marker) (match-beginning 0))
					(set-marker (make-marker) (match-beginning 0))
					nil)
		       (yas/field-mirrors field))
		 (delete-region (match-beginning 0) (match-end 0)))))))))

(defun yas/update-mirrors (snippet)
  (save-excursion
  (dolist (field (yas/snippet-fields snippet))
    (dolist (mirror (yas/field-mirrors field))
      (yas/mirror-update-display mirror field)))))

(defun yas/mirror-update-display (mirror field)
  (goto-char (yas/mirror-start mirror))
  (delete-region (yas/mirror-start mirror) (yas/mirror-end mirror))
  (insert (yas/apply-transform mirror field))
  (set-marker (yas/mirror-end mirror) (point)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Template-related and snippet loading functions

(defun yas/parse-template (&optional file-name)
  "Parse the template in the current buffer.
If the buffer contains a line of \"# --\" then the contents
above this line are ignored. Variables can be set above this
line through the syntax:

#name : value

Here's a list of currently recognized variables:

 * name
 * contributor
 * condition

#name: #include \"...\"
# --
#include \"$1\""
  (goto-char (point-min))
  (let ((name file-name) template bound condition)
    (if (re-search-forward "^# --\n" nil t)
        (progn (setq template
                     (buffer-substring-no-properties (point)
                                                     (point-max)))
               (setq bound (point))
               (goto-char (point-min))
               (while (re-search-forward "^#\\([^ ]+\\) *: *\\(.*\\)$" bound t)
                 (when (string= "name" (match-string-no-properties 1))
                   (setq name (match-string-no-properties 2)))
                 (when (string= "condition" (match-string-no-properties 1))
                   (setq condition (read (match-string-no-properties 2))))))
      (setq template
            (buffer-substring-no-properties (point-min) (point-max))))
    (list template name condition)))

(defun yas/directory-files (directory file?)
  "Return directory files or subdirectories in full path."
  (remove-if (lambda (file)
               (or (string-match "^\\."
                                 (file-name-nondirectory file))
                   (if file?
                       (file-directory-p file)
                     (not (file-directory-p file)))))
             (directory-files directory t)))

(defun yas/make-menu-binding (template)
  (lexical-let ((template template))
    (lambda ()
      (interactive)
      (yas/expand-snippet (point)
                          (point)
                          template))))

(defun yas/modify-alist (alist key value)
  "Modify ALIST to map KEY to VALUE. return the new alist."
  (let ((pair (assoc key alist)))
    (if (null pair)
        (cons (cons key value)
              alist)
      (setcdr pair value)
      alist)))

(defun yas/fake-keymap-for-popup (templates)
  "Create a fake keymap for popup menu usage."
  (cons 'keymap
        (mapcar (lambda (pair)
                  (let* ((template (cdr pair))
                         (name (yas/template-name template))
                         (content (yas/template-content template)))
                    (list content 'menu-item name t)))
                templates)))

(defun yas/point-to-coord (&optional point)
  "Get the xoffset/yoffset information of POINT.
If POINT is not given, default is to current point.
If `posn-at-point' is not available (like in Emacs 21.3),
t is returned simply."
  (if (fboundp 'posn-at-point)
      (let ((x-y (posn-x-y (posn-at-point (or point (point))))))
        (list (list (+ (car x-y) 10)
                    (+ (cdr x-y) 20))
              (selected-window)))
    t))

(defun yas/x-popup-menu-for-template (templates)
  "Show a popup menu listing templates to let the user select one."
  (car (x-popup-menu (yas/point-to-coord)
                     (yas/fake-keymap-for-popup templates))))
(defun yas/text-popup-for-template (templates)
  "Can't display popup menu in text mode. Just select the first one."
  (yas/template-content (cdar templates)))
(defun yas/dropdown-list-popup-for-template (templates)
  "Use dropdown-list.el to popup for templates. Better than the
default \"select first\" behavior of `yas/text-popup-for-template'.
You can also use this in window-system.

NOTE: You need to download and install dropdown-list.el to use this."
  (if (fboundp 'dropdown-list)
      (let ((n (dropdown-list (mapcar (lambda (i)
                                        (yas/template-name
                                         (cdr i)))
                                      templates))))
        (if n
            (yas/template-content
             (cdr (nth n templates)))
          nil))
    (error "Please download and install dropdown-list.el to use this")))

(defun yas/popup-for-template (templates)
  (if window-system
      (funcall yas/window-system-popup-function templates)
    (funcall yas/text-popup-function templates)))

(defun yas/load-directory-1 (directory &optional parent)
  "Really do the job of loading snippets from a directory
hierarchy."
  (let ((mode-sym (intern (file-name-nondirectory directory)))
        (snippets nil))
    (with-temp-buffer
      (dolist (file (yas/directory-files directory t))
        (when (file-readable-p file)
          (insert-file-contents file nil nil nil t)
          (let ((snippet-file-name (file-name-nondirectory file)))
            (push (cons snippet-file-name
                        (yas/parse-template snippet-file-name))
                  snippets)))))
    (yas/define-snippets mode-sym
                         snippets
                         parent)
    (dolist (subdir (yas/directory-files directory nil))
      (yas/load-directory-1 subdir mode-sym))))

(defun yas/quote-string (string)
  "Escape and quote STRING.
foo\"bar\\! -> \"foo\\\"bar\\\\!\""
  (concat "\""
          (replace-regexp-in-string "[\\\"]"
                                    "\\\\\\&"
                                    string
                                    t)
          "\""))

(defun yas/compile-bundle
  (&optional yasnippet yasnippet-bundle snippet-roots code)
  "Compile snippets in SNIPPET-ROOTS to a single bundle file.
SNIPPET-ROOTS is a list of root directories that contains the snippets
definition. YASNIPPET is the yasnippet.el file path. YASNIPPET-BUNDLE
is the output file of the compile result. CODE is the code you would
like to used to initialize yasnippet. Here's the default value for
all the parameters:

 (yas/compile-bundle \"yasnippet.el\"
                     \"./yasnippet-bundle.el\"
                     '(\"snippets\")
                     \"(yas/initialize)\")"
  (when (null yasnippet)
    (setq yasnippet "yasnippet.el"))
  (when (null yasnippet-bundle)
    (setq yasnippet-bundle "./yasnippet-bundle.el"))
  (when (null snippet-roots)
    (setq snippet-roots '("snippets")))
  (when (null code)
    (setq code "(yas/initialize)"))

  (let ((dirs (or (and (listp snippet-roots) snippet-roots)
                  (list snippet-roots)))
        (bundle-buffer nil))
    (with-temp-buffer
      (setq bundle-buffer (current-buffer))
      (insert-file-contents yasnippet)
      (goto-char (point-max))
      (insert ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n")
      (insert ";;;;      Auto-generated code         ;;;;\n")
      (insert ";;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;\n")
      (insert code "\n")
      (flet ((yas/define-snippets
              (mode snippets &optional parent)
              (with-current-buffer bundle-buffer
                (insert ";;; snippets for " (symbol-name mode) "\n")
                (insert "(yas/define-snippets '" (symbol-name mode) "\n")
                (insert "'(\n")
                (dolist (snippet snippets)
                  (insert "  ("
                          (yas/quote-string (car snippet))
                          " "
                          (yas/quote-string (cadr snippet))
                          " "
                          (if (caddr snippet)
                              (yas/quote-string (caddr snippet))
                            "nil")
                          " "
                          (if (nth 3 snippet)
                              (format "'%s" (nth 3 snippet))
                            "nil")
                          ")\n"))
                (insert "  )\n")
                (insert (if parent
                            (concat "'" (symbol-name parent))
                          "nil")
                        ")\n\n"))))
        (dolist (dir dirs)
          (dolist (subdir (yas/directory-files dir nil))
            (yas/load-directory-1 subdir nil))))
      (insert "(provide '"
              (file-name-nondirectory
               (file-name-sans-extension
                yasnippet-bundle))
              ")\n")
      (setq buffer-file-name yasnippet-bundle)
      (save-buffer))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; User level functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun yas/about ()
  (interactive)
  (message (concat "yasnippet (version "
                   yas/version
                   ") -- pluskid <pluskid@gmail.com>")))
(defun yas/reload-all ()
  "Reload all snippets."
  (interactive)
  (if yas/root-directory
      (if (listp yas/root-directory)
          (dolist (directory yas/root-directory)
            (yas/load-directory directory))
        (yas/load-directory yas/root-directory))
    (call-interactively 'yas/load-directory))
  (message "done."))

(defun yas/load-directory (directory)
  "Load snippet definition from a directory hierarchy.
Below the top-level directory, each directory is a mode
name.  And under each subdirectory, each file is a definition
of a snippet.  The file name is the trigger key and the
content of the file is the template."
  (interactive "DSelect the root directory: ")
  (unless (file-directory-p directory)
    (error "Error %s not a directory" directory))
  (add-to-list 'yas/root-directory directory)
  (dolist (dir (yas/directory-files directory nil))
    (yas/load-directory-1 dir))
  (when (interactive-p)
    (message "done.")))

(defun yas/initialize ()
  "Do necessary initialization."
  (add-hook 'after-change-major-mode-hook
            'yas/minor-mode-auto-on)
  (dolist (hook yas/extra-mode-hooks)
    (add-hook hook
              'yas/minor-mode-auto-on))
  (add-hook 'yas/minor-mode-on-hook
            'yas/ensure-minor-mode-priority)
  (when yas/use-menu
    (define-key-after
      (lookup-key global-map [menu-bar])
      [yasnippet]
      (cons "YASnippet" yas/menu-keymap)
      'buffer)))

(defun yas/define-snippets (mode snippets &optional parent-mode)
  "Define snippets for MODE.  SNIPPETS is a list of
snippet definition, of the following form:

 (KEY TEMPLATE NAME CONDITION)

or the NAME and CONDITION may be omitted.  The optional 3rd
parameter can be used to specify the parent mode of MODE.  That
is, when looking a snippet in MODE failed, it can refer to its
parent mode.  The PARENT-MODE may not need to be a real mode."
  (let ((snippet-table (yas/snippet-table mode))
        (parent-table (if parent-mode
                          (yas/snippet-table parent-mode)
                        nil))
        (keymap (if yas/use-menu
                    (yas/menu-keymap-for-mode mode)
                  nil)))
    (when parent-table
      (setf (yas/snippet-table-parent snippet-table)
            parent-table)
      (when yas/use-menu
        (define-key keymap (vector 'parent-mode)
          `(menu-item "parent mode"
                      ,(yas/menu-keymap-for-mode parent-mode)))))
    (when (and yas/use-menu
               (yas/real-mode? mode))
      (define-key yas/menu-keymap (vector mode)
        `(menu-item ,(symbol-name mode) ,keymap)))
    (dolist (snippet snippets)
      (let* ((full-key (car snippet))
             (key (file-name-sans-extension full-key))
             (name (or (caddr snippet) (file-name-extension full-key)))
             (condition (nth 3 snippet))
             (template (yas/make-template (cadr snippet)
                                          (or name key)
                                          condition)))
        (yas/snippet-table-store snippet-table
                                 full-key
                                 key
                                 template)
        (when yas/use-menu
          (define-key keymap (vector (make-symbol full-key))
            `(menu-item ,(yas/template-name template)
                        ,(yas/make-menu-binding (yas/template-content template))
                        :keys ,(concat key yas/trigger-symbol))))))))

(defun yas/set-mode-parent (mode parent)
  "Set parent mode of MODE to PARENT."
  (setf (yas/snippet-table-parent
         (yas/snippet-table mode))
        (yas/snippet-table parent))
  (when yas/use-menu
    (define-key (yas/menu-keymap-for-mode mode) (vector 'parent-mode)
      `(menu-item "parent mode"
                  ,(yas/menu-keymap-for-mode parent)))))

(defun yas/define (mode key template &optional name condition)
  "Define a snippet.  Expanding KEY into TEMPLATE.
NAME is a description to this template.  Also update
the menu if `yas/use-menu' is `t'.  CONDITION is the
condition attached to this snippet.  If you attach a
condition to a snippet, then it will only be expanded
when the condition evaluated to non-nil."
  (yas/define-snippets mode
                       (list (list key template name condition))))


(defun yas/hippie-try-expand (first-time?)
  "Integrate with hippie expand.  Just put this function in
`hippie-expand-try-functions-list'."
  (if (not first-time?)
      (let ((yas/fallback-behavior 'return-nil))
        (yas/expand))
    (when (and (null (car buffer-undo-list))
               (eq 'apply
                   (car (cadr buffer-undo-list)))
               (eq 'yas/undo-expand-snippet
                   (cadr (cadr buffer-undo-list))))
      (undo 1))
    nil))

(defun yas/expand ()
  "Expand a snippet."
  (interactive)
  (let ((local-condition (yas/template-condition-predicate
                          yas/buffer-local-condition)))
    (if local-condition
        (let ((yas/require-template-condition
               (if (and (consp local-condition)
                        (eq 'require-snippet-condition (car local-condition))
                        (symbolp (cdr local-condition)))
                   (cdr local-condition)
                 nil)))
          (multiple-value-bind (templates start end) (yas/current-key)
            (if templates
                (let ((template (if (null (cdr templates)) ; only 1 template
                                    (yas/template-content (cdar templates))
                                  (yas/popup-for-template templates))))
                  (if template
                      (progn (yas/expand-snippet start end template)
                             'expanded) ; expanded successfully
                    'interrupted))     ; interrupted by user
              (if (eq yas/fallback-behavior 'return-nil)
                  nil                   ; return nil
                (let* ((yas/minor-mode nil)
                       (command (key-binding yas/trigger-key)))
                  (when (commandp command)
                    (call-interactively command))))))))))

(defun yas/field-probably-deleted-p (field)
  "Guess if FIELD was deleted because of his parent-field" 
  (and (zerop (- (yas/field-start field) (yas/field-end field)))
       (yas/field-parent-field field)))

(defun yas/snippets-at-point ()
  (sort
   (remove nil (mapcar #'(lambda (ov)
			   (overlay-get ov 'yas/snippet))
		       (overlays-at (point))))
   #'(lambda (s1 s2)
       (>= (yas/snippet-id s2) (yas/snippet-id s1)))))

(defun yas/next-field (&optional arg)
  "Navigate to next field.  If there's none, exit the snippet."
  (interactive)
  (let* ((arg (or arg
                  1))
         (snippet (first (yas/snippets-at-point)))
	 (active-field (overlay-get yas/active-field-overlay 'yas/field))
         (number (and snippet
                      (+ arg
                         (yas/field-number active-field))))
         (live-fields (remove-if #'yas/field-probably-deleted-p (yas/snippet-fields snippet)))
         (target-field (yas/snippet-find-field snippet number)))
    (cond ((and number
                (> number (length live-fields)))
           (yas/exit-snippet snippet))
          (target-field
           (yas/move-to-field snippet target-field))
          (t
           nil))))

(defun yas/make-move-active-field-overlay (snippet field)
  (if (and yas/active-field-overlay
	   (overlay-buffer yas/active-field-overlay))
      (move-overlay yas/active-field-overlay
		    (yas/field-start field)
		    (yas/field-end field))
    (setq yas/active-field-overlay
	  (make-overlay (yas/field-start field)
			(yas/field-end field)
			nil nil t))
    (overlay-put yas/active-field-overlay 'face 'yas/field-highlight-face)
    ;;(overlay-put yas/active-field-overlay 'evaporate t)
    (overlay-put yas/active-field-overlay 'modification-hooks '(yas/on-field-overlay-modification))
    (overlay-put yas/active-field-overlay 'insert-in-front-hooks '(yas/on-field-overlay-modification))
    (overlay-put yas/active-field-overlay 'insert-behind-hooks '(yas/on-field-overlay-modification))))

(defun yas/make-move-field-protection-overlays (snippet field)
  (cond ((and yas/field-protection-overlays
	      (every #'overlay-buffer yas/field-protection-overlays))
	 (move-overlay (first yas/field-protection-overlays) (1- (yas/field-start field)) (yas/field-start field))
	 (move-overlay (second yas/field-protection-overlays) (yas/field-end field) (1+ (yas/field-end field))))
	(t
	 (setq yas/field-protection-overlays
	       (list (make-overlay (1- (yas/field-start field)) (yas/field-start field) nil t nil)
		     (make-overlay (yas/field-end field) (1+ (yas/field-end field)) nil t nil)))
	 (dolist (ov yas/field-protection-overlays)
	   (overlay-put ov 'face 'yas/field-debug-face)
	   ;; (overlay-put ov 'evaporate t)
	   (overlay-put ov 'modification-hooks '(yas/on-protection-overlay-modification))))))


(defun yas/move-to-field (snippet field)
  "Update SNIPPET to move to field FIELD.

Also create some protection overlays"
  (goto-char (yas/field-start field))
  (setf (yas/snippet-active-field snippet) field)
  (yas/make-move-active-field-overlay snippet field)
  (yas/make-move-field-protection-overlays snippet field)
  (overlay-put yas/active-field-overlay 'yas/field field))

(defun yas/prev-field ()
  "Navigate to prev field.  If there's none, exit the snippet."
  (interactive)
  (yas/next-field -1))

(defun yas/exit-snippet (snippet)
  "Goto exit-marker of SNIPPET and commit the snippet.  Cleaning
up the snippet does not delete it!"
  (interactive)
  (goto-char (if (yas/snippet-exit snippet)
		 (yas/snippet-exit snippet)
	       (overlay-end (yas/snippet-control-overlay snippet)))))

(defun yas/exterminate-snippets ()
  "Remove all snippets in buffer"
  (interactive)
  (mapcar #'yas/commit-snippet (remove nil (mapcar #'(lambda (ov)
						       (overlay-get ov 'yas/snippet))
						   (overlays-in (point-min) (point-max))))))

(defun yas/delete-overlay-region (overlay)
  (delete-region (overlay-start overlay) (overlay-end overlay)))

(defun yas/markers-to-points (snippet)
  "Convert all markers in SNIPPET to simple integer buffer positions."
  (dolist (field (yas/snippet-fields snippet))
    (let ((start (marker-position (yas/field-start field)))
	  (end (marker-position (yas/field-end field))))
      (set-marker (yas/field-start field) nil)
      (set-marker (yas/field-end field) nil)
      (setf (yas/field-start field) start)
      (setf (yas/field-end field) end))
    (dolist (mirror (yas/field-mirrors field))
      (let ((start (marker-position (yas/mirror-start mirror)))
	    (end (marker-position (yas/mirror-end mirror))))
	(set-marker (yas/mirror-start mirror) nil)
	(set-marker (yas/mirror-end mirror) nil)
	(setf (yas/mirror-start mirror) start)
	(setf (yas/mirror-end mirror) end))))
  (when (yas/snippet-exit snippet)
    (let ((exit (marker-position (yas/snippet-exit snippet))))
      (set-marker (yas/snippet-exit snippet) nil)
      (setf (yas/snippet-exit snippet) exit))))

(defun yas/points-to-markers (snippet)
  "Convert all simple integer buffer positions in SNIPPET to markers"
  (dolist (field (yas/snippet-fields snippet))
    (setf (yas/field-start field) (set-marker (make-marker) (yas/field-start field)))
    (setf (yas/field-end field) (set-marker (make-marker) (yas/field-end field)))
    (dolist (mirror (yas/field-mirrors field))
      (setf (yas/mirror-start mirror) (set-marker (make-marker) (yas/mirror-start mirror)))
      (setf (yas/mirror-end mirror) (set-marker (make-marker) (yas/mirror-end mirror)))))
  (when (yas/snippet-exit snippet)
    (setf (yas/snippet-exit snippet) (set-marker (make-marker) (yas/snippet-exit snippet)))))

(defun yas/commit-snippet (snippet &optional no-hooks)
  "Commit SNIPPET, but leave point as it is.  This renders the
snippet as ordinary text.

Return a buffer position where the point should be placed if
exiting the snippet."
  (let ((control-overlay (yas/snippet-control-overlay snippet))
         yas/snippet-beg
         yas/snippet-end)
    ;;
    ;; Save the end of the moribund snippet in case we need to revive it
    ;; its original expansion.
    ;;
    (when (and control-overlay
               (overlay-buffer control-overlay))
      (setq yas/snippet-beg (overlay-start control-overlay))
      (setq yas/snippet-end (overlay-end control-overlay))
      (delete-overlay control-overlay))

    (let ((inhibit-modification-hooks t))
      (when yas/active-field-overlay
	(delete-overlay yas/active-field-overlay))
      (when yas/field-protection-overlays
	(mapcar #'delete-overlay yas/field-protection-overlays)))

    (yas/markers-to-points snippet)

    ;; Push an action for snippet revival
    ;;
    (push `(apply yas/snippet-revive ,yas/snippet-beg ,yas/snippet-end ,snippet)
	  buffer-undo-list)
    
    ;; XXX: `yas/after-exit-snippet-hook' should be run with
    ;; `yas/snippet-beg' and `yas/snippet-end' bound. That might not
    ;; be the case if the main overlay had somehow already
    ;; disappeared, which sometimes happens when the snippet's messed
    ;; up...
    ;;
    (unless no-hooks (run-hooks 'yas/after-exit-snippet-hook))))

(defun yas/check-commit-snippet ()
  "Checks if point exited the currently active field of the
snippet, if so cleans up the whole snippet up."
  (let* ((snippet (first (yas/snippets-at-point))))
    (cond ((null snippet)
	   ;;
	   ;; No snippet at point, cleanup *all* snippets
	   ;;
	   (yas/exterminate-snippets))
	  ((let ((beg (overlay-start yas/active-field-overlay))
		 (end (overlay-end yas/active-field-overlay)))
	     (or (not end)
		 (not beg)
		 (> (point) end)
		 (< (point) beg)))
	   ;; A snippet exitss at point, but point left the currently
	   ;; active field overlay
	   (yas/commit-snippet snippet))
	  ( ;;
	   ;; Snippet at point, and point inside a snippet field,
	   ;; everything is normal
	     ;;
	   t
	   nil))))

;;
;; Pre and post command handlers
;;
(defun yas/pre-command-handler ()
  )

(defun yas/post-command-handler ()
  (cond ((eq 'undo this-command)
	 (let ((snippet (car (yas/snippets-at-point))))
	   (when snippet
	     (yas/move-to-field snippet (or (yas/snippet-active-field snippet)
					    (car (yas/snippet-fields snippet)))))))
	((not (yas/undo-in-progress))
	 (yas/check-commit-snippet))))

;; Debug functions.  Use (or change) at will whenever needed.

(defun yas/debug-some-vars ()
  (interactive)
  (with-output-to-temp-buffer "*YASnippet trace*"
    (princ "Interesting YASnippet vars: \n\n")

    (princ (format "\nPost command hook: %s\n" post-command-hook))
    (princ (format "\nPre  command hook: %s\n" pre-command-hook))

    (princ (format "\nUndo is %s and point-max is %s.\n"
                   (if (eq buffer-undo-list t)
                       "DISABLED"
                     "ENABLED")
                   (point-max)))
    (unless (eq buffer-undo-list t)
      (princ (format "Undpolist has %s elements. First 10 elements follow:\n" (length buffer-undo-list)))
      (let ((first-ten (subseq buffer-undo-list 0 19)))
        (dolist (undo-elem first-ten)
          (princ (format "%2s:  %s\n" (position undo-elem first-ten) (truncate-string-to-width (format "%s" undo-elem) 70))))))))


(defun yas/exterminate-package ()
  (interactive)
  (yas/minor-mode -1)
  (mapatoms #'(lambda (atom)
                (when (string-match "yas/" (symbol-name atom))
                  (unintern atom)))))

(defun yas/debug-test (&optional quiet)
  (interactive "P")
  (yas/load-directory "~/Source/yasnippet/snippets/")
  ;;(kill-buffer (get-buffer "*YAS TEST*"))
  (set-buffer (switch-to-buffer "*YAS TEST*"))
  (yas/exterminate-snippets)
  (erase-buffer)
  (setq buffer-undo-list nil)
  (html-mode)
  (yas/minor-mode)
  (let ((abbrev))
    ;; (if (require 'ido nil t)
    ;; 	(setq abbrev (ido-completing-read "Snippet abbrev: " '("crazy" "prip" "prop")))
    ;;   (setq abbrev "prop"))
    (setq abbrev "bosta")
    (insert abbrev))
  (unless quiet
    (add-hook 'post-command-hook 'yas/debug-some-vars 't 'local))
  )
  

(provide 'yasnippet)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Monkey patching for other functions that's causing
;; problems to yasnippet. For details on why I patch
;; those functions, refer to
;;   http://code.google.com/p/yasnippet/wiki/MonkeyPatching
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defadvice c-neutralize-syntax-in-CPP
  (around yas-mp/c-neutralize-syntax-in-CPP activate)
  "Adviced `c-neutralize-syntax-in-CPP' to properly
handle the end-of-buffer error fired in it by calling
`forward-char' at the end of buffer."
  (condition-case err
      ad-do-it
    (error (message (error-message-string err)))))
