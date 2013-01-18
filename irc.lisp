(defpackage #:irc-client
  (:use #:cl #:sys.net)
  (:export lrssl))

(in-package #:irc-client)

(defparameter *numeric-replies*
  '((401 :err-no-such-nick)
    (402 :err-no-such-server)
    (403 :err-no-such-channel)
    (404 :err-cannot-send-to-channel)
    (405 :err-too-many-channels)
    (406 :err-was-no-such-nick)
    (407 :err-too-many-targets)
    (409 :err-no-origin)
    (411 :err-no-recipient)
    (412 :err-no-text-to-send)
    (413 :err-no-toplevel)
    (414 :err-wild-toplevel)
    (421 :err-unknown-command)
    (422 :err-no-motd)
    (423 :err-no-admin-info)
    (424 :err-file-error)
    (431 :err-no-nickname-given)
    (432 :err-erroneus-nickname)
    (433 :err-nickname-in-use)
    (436 :err-nick-collision)
    (441 :err-user-not-in-channel)
    (442 :err-not-on-channel)
    (443 :err-user-on-channel)
    (444 :err-no-login)
    (445 :err-summon-disabled)
    (446 :err-users-disabled)
    (451 :err-not-registered)
    (461 :err-need-more-params)
    (462 :err-already-registred)
    (463 :err-no-perm-for-host)
    (464 :err-password-mismatch)
    (465 :err-youre-banned-creep)
    (467 :err-key-set)
    (471 :err-channel-is-full)
    (472 :err-unknown-mode)
    (473 :err-invite-only-chan)
    (474 :err-banned-from-chan)
    (475 :err-bad-channel-key)
    (481 :err-no-privileges)
    (482 :err-chanop-privs-needed)
    (483 :err-cant-kill-server)
    (491 :err-no-oper-host)
    (501 :err-umode-unknown-flag)
    (502 :err-users-dont-match)
    (300 :rpl-none)
    (302 :rpl-userhost)
    (303 :rpl-ison)
    (301 :rpl-away)
    (305 :rpl-unaway)
    (306 :rpl-nowaway)
    (311 :rpl-whoisuser)
    (312 :rpl-whoisserver)
    (313 :rpl-whoisoperator)
    (317 :rpl-whoisidle)
    (318 :rpl-endofwhois)
    (319 :rpl-whoischannels)
    (314 :rpl-whowasuser)
    (369 :rpl-endofwhowas)
    (321 :rpl-liststart)
    (322 :rpl-list)
    (323 :rpl-listend)
    (324 :rpl-channelmodeis)
    (331 :rpl-notopic)
    (332 :rpl-topic)
    (333 :rpl-topic-time)
    (341 :rpl-inviting)
    (342 :rpl-summoning)
    (351 :rpl-version)
    (352 :rpl-whoreply)
    (315 :rpl-endofwho)
    (353 :rpl-namreply)
    (366 :rpl-endofnames)
    (364 :rpl-links)
    (365 :rpl-endoflinks)
    (367 :rpl-banlist)
    (368 :rpl-endofbanlist)
    (371 :rpl-info)
    (374 :rpl-endofinfo)
    (375 :rpl-motdstart)
    (372 :rpl-motd)
    (376 :rpl-endofmotd)
    (381 :rpl-youreoper)
    (382 :rpl-rehashing)
    (391 :rpl-time)
    (392 :rpl-usersstart)
    (393 :rpl-users)
    (394 :rpl-endofusers)
    (395 :rpl-nousers)
    (200 :rpl-tracelink)
    (201 :rpl-traceconnecting)
    (202 :rpl-tracehandshake)
    (203 :rpl-traceunknown)
    (204 :rpl-traceoperator)
    (205 :rpl-traceuser)
    (206 :rpl-traceserver)
    (208 :rpl-tracenewtype)
    (261 :rpl-tracelog)
    (211 :rpl-statslinkinfo)
    (212 :rpl-statscommands)
    (213 :rpl-statscline)
    (214 :rpl-statsnline)
    (215 :rpl-statsiline)
    (216 :rpl-statskline)
    (218 :rpl-statsyline)
    (219 :rpl-endofstats)
    (241 :rpl-statslline)
    (242 :rpl-statsuptime)
    (243 :rpl-statsoline)
    (244 :rpl-statshline)
    (221 :rpl-umodeis)
    (251 :rpl-luserclient)
    (252 :rpl-luserop)
    (253 :rpl-luserunknown)
    (254 :rpl-luserchannels)
    (255 :rpl-luserme)
    (256 :rpl-adminme)
    (257 :rpl-adminloc1)
    (258 :rpl-adminloc2)
    (259 :rpl-adminemail)))

(defun decode-command (line)
  "Explode a line into (prefix command parameters...)."
  ;; <message>  ::= [':' <prefix> <SPACE> ] <command> <params> <crlf>
  ;; <prefix>   ::= <servername> | <nick> [ '!' <user> ] [ '@' <host> ]
  ;; <command>  ::= <letter> { <letter> } | <number> <number> <number>
  ;; <SPACE>    ::= ' ' { ' ' }
  ;; <params>   ::= <SPACE> [ ':' <trailing> | <middle> <params> ]
  (let ((prefix nil)
        (offset 0)
        (command nil)
        (parameters '()))
    (when (and (not (zerop (length line)))
               (eql (char line 0) #\:))
      ;; Prefix present, read up to a space.
      (do () ((or (>= offset (length line))
                  (eql (char line offset) #\Space)))
        (incf offset))
      (setf prefix (subseq line 1 offset)))
    ;; Eat leading spaces.
    (do () ((or (>= offset (length line))
                (not (eql (char line offset) #\Space))))
      (incf offset))
    ;; Parse a command, reading until space or the end.
    (let ((start offset))
      (do () ((or (>= offset (length line))
                  (eql (char line offset) #\Space)))
        (incf offset))
      (setf command (subseq line start offset)))
    (when (and (= (length command) 3)
               (every (lambda (x) (find x "1234567890")) command))
      (setf command (parse-integer command))
      (setf command (or (second (assoc command *numeric-replies*))
                        command)))
    ;; Read parameters.
    (loop
       ;; Eat leading spaces.
       (do () ((or (>= offset (length line))
                   (not (eql (char line offset) #\Space))))
         (incf offset))
       (cond ((>= offset (length line)) (return))
             ((eql (char line offset) #\:)
              (push (subseq line (1+ offset)) parameters)
              (return))
             (t (let ((start offset))
                  (do () ((or (>= offset (length line))
                              (eql (char line offset) #\Space)))
                    (incf offset))
                  (push (subseq line start offset) parameters)))))
    (values prefix command (nreverse parameters))))

(defun parse-command (line)
  (let ((command-end nil)
        (rest-start nil)
        (rest-end nil))
    (dotimes (i (length line))
      (when (eql (char line i) #\Space)
        (setf command-end i
              rest-start i)
        (return)))
    (when rest-start
      ;; Eat leading spaces.
      (do () ((or (>= rest-start (length line))
                  (not (eql (char line rest-start) #\Space))))
        (incf rest-start)))
    (values (subseq line 1 command-end)
            (subseq line (or rest-start (length line)) rest-end))))

(defun send (stream control-string &rest arguments)
  "Buffered FORMAT."
  (declare (dynamic-extent argument))
  (write-sequence (apply 'format nil control-string arguments) stream))

(defvar *command-table* (make-hash-table :test 'equal))

(defmacro define-server-command (name (state . lambda-list) &body body)
  (let ((args (gensym)))
    `(setf (gethash ,(if (and (symbolp name) (not (keywordp name)))
                         (symbol-name name)
                         name)
                    *command-table*)
           (lambda (,state ,(first lambda-list) ,args)
             (declare (system:lambda-name (irc-command ,name)))
             (destructuring-bind ,(rest lambda-list) ,args
               ,@body)))))

(define-server-command privmsg (irc from channel message)
  ;; ^AACTION [msg]^A is a /me command.
  (cond ((and (>= (length message) 9)
              (eql (char message 0) (code-char #x01))
              (eql (char message (1- (length message))) (code-char #x01))
              (string= "ACTION " message :start2 1 :end2 8))
         (format t "[~A]* ~A ~A~%" channel from
                 (subseq message 8 (1- (length message)))))
        (t (format t "[~A]<~A> ~A~%" channel from message))))

(defvar *known-servers*
  '((:freenode (213 92 8 4) 6667))
  "A list of known/named IRC servers.")

(defun resolve-server-name (name)
  (let ((known (assoc name *known-servers* :key 'symbol-name :test 'string-equal)))
    (cond (known
           (values (second known) (third known)))
          (t (error "Unknown server ~S~%" name)))))

(defclass irc-client (sys.graphics::character-input-mixin
                      sys.graphics::window-with-chrome
                      sys.int::edit-stream
                      sys.int::stream-object)
  ((command-process :reader irc-command-process)
   (receive-process :reader irc-receive-process)
   (connection :initform nil :accessor irc-connection)
   (input :reader irc-input)
   (display :reader irc-display)
   (current-channel :initform nil :accessor current-channel)
   (joined-channels :initform '() :accessor joined-channels)
   (nickname :initarg :nickname :accessor nickname))
  (:default-initargs :nickname nil))

;;; This is just so the graphics manager knows the display needs an update.
(defclass irc-display (sys.graphics::text-widget) ())
(defmethod sys.int::stream-write-char :after (character (stream irc-display))
  (setf sys.graphics::*refresh-required* t))

(defmethod initialize-instance :after ((instance irc-client))
  (multiple-value-bind (left right top bottom)
      (sys.graphics::compute-window-margins instance)
    (setf (slot-value instance 'display) (make-instance 'irc-display
                                                        :framebuffer (sys.graphics::window-backbuffer instance)
                                                        :x left
                                                        :y top
                                                        :width (- (array-dimension (sys.graphics::window-backbuffer instance) 1)
                                                                  left right)
                                                        :height (- (array-dimension (sys.graphics::window-backbuffer instance) 0)
                                                                   top bottom 1 16)))
    (setf (slot-value instance 'input) (make-instance 'sys.graphics::text-widget
                                                      :framebuffer (sys.graphics::window-backbuffer instance)
                                                      :x left
                                                      :y (+ top
                                                            (- (array-dimension (sys.graphics::window-backbuffer instance) 0)
                                                               top bottom 1 16)
                                                            1)
                                                      :width (- (array-dimension (sys.graphics::window-backbuffer instance) 1)
                                                                left right)
                                                      :height 16)))
  (let ((cmd (sys.int::make-process "IRC command"))
        (rcv (sys.int::make-process "IRC receive")))
    (setf (slot-value instance 'command-process) cmd)
    (setf (slot-value instance 'receive-process) rcv)
    (sys.int::process-preset cmd 'irc-top-level instance)
    (sys.int::process-preset rcv 'irc-receive instance)
    (sys.int::process-enable cmd)
    (sys.int::process-enable rcv)))

;;; The IRC-CLIENT stream is used to read/write from the input line, not from
;;; the display.
;;; Edit-stream expects the stream to be able to do input and output, so
;;; *STANDARD-INPUT* is bound to this stream (with line-editing) and
;;; *STANDARD-OUTPUT* is bound to the display text widget (no input).
;;; READ-CHAR is provided by Character-Input-Mixin.
(defmethod sys.int::stream-write-char (character (stream irc-client))
  (sys.int::stream-write-char character (irc-input stream))
  (setf sys.graphics::*refresh-required* t))
(defmethod sys.int::stream-start-line-p ((stream irc-client))
  (sys.int::stream-start-line-p (irc-input stream)))
(defmethod sys.int::stream-cursor-pos ((stream irc-client))
  (sys.int::stream-cursor-pos (irc-input stream)))
(defmethod sys.int::stream-move-to ((stream irc-client) x y)
  (sys.int::stream-move-to (irc-input stream) x y))
(defmethod sys.int::stream-character-width ((stream irc-client) character)
  (sys.int::stream-character-width (irc-input stream) character))
(defmethod sys.int::stream-compute-motion ((stream irc-client) string &optional (start 0) end initial-x initial-y)
  (sys.int::stream-compute-motion (irc-input stream) string start end initial-x initial-y))
(defmethod sys.int::stream-clear-between ((stream irc-client) start-x start-y end-x end-y)
  (sys.int::stream-clear-between (irc-input stream) start-x start-y end-x end-y)
  (setf sys.graphics::*refresh-required* t))
(defmethod sys.int::stream-element-type* ((stream irc-client))
  'character)

(defmethod sys.graphics::window-close-event ((irc irc-client))
  (sys.int::process-disable (irc-command-process irc))
  (sys.int::process-disable (irc-receive-process irc))
  (when (irc-connection irc)
    (close (irc-connection irc)))
  (sys.graphics::close-window irc))

(defmethod sys.graphics::window-redraw ((window irc-client))
  (multiple-value-bind (left right top bottom)
      (sys.graphics::compute-window-margins window)
    (sys.graphics::bitset (sys.graphics::window-height window) (sys.graphics::window-width window)
                          (sys.graphics::window-background-colour (irc-display window))
                          (sys.graphics::window-backbuffer window) top left)
    (sys.graphics::bitset 1 (sys.graphics::window-width window)
                          (sys.graphics::make-colour :gray)
                          (sys.graphics::window-backbuffer window)
                          (+ top
                             (- (array-dimension (sys.graphics::window-backbuffer window) 0)
                                top bottom 1 16))
                          left)))

(defun irc-receive (irc)
  (let ((*standard-input* irc)
        (*standard-output* (irc-display irc))
        (*error-output* (irc-display irc))
        (*query-io* (make-two-way-stream irc (irc-display irc)))
        (*debug-io* (make-two-way-stream irc (irc-display irc))))
    ;; Should close the connection here...
    (with-simple-restart (abort "Give up")
      (sys.int::process-wait "Awaiting connection" (lambda () (irc-connection irc)))
      (let ((connection (irc-connection irc)))
        (loop (let ((line (read-line connection)))
                (multiple-value-bind (prefix command parameters)
                    (decode-command line)
                  (let ((fn (gethash command *command-table*)))
                    (cond (fn (funcall fn irc prefix parameters))
                          ((keywordp command)
                           (format t "[~A] -!- ~A~%" prefix (car (last parameters))))
                          ((integerp command)
                           (format t "[~A] ~D ~A~%" prefix command parameters))
                          (t (write-line line)))))))))))

(defvar *top-level-commands* (make-hash-table :test 'equal))

(defmacro define-command (name (irc text) &body body)
  `(setf (gethash ',(string-upcase (string name))
                  *top-level-commands*)
         (lambda (,irc ,text)
           (declare (system:lambda-name (irc-command ,name)))
           ,@body)))

(define-condition quit-irc () ())

(define-command quit (irc text)
  (when (irc-connection irc)
    (send (irc-connection irc) "QUIT :~A~%" text))
  (signal 'quit-irc))

(define-command raw (irc text)
  (when (irc-connection irc)
    (write-string text (irc-connection irc))
    (terpri (irc-connection irc))))

(define-command eval (irc text)
  (declare (ignore irc))
  (format t "[eval] ~A~%" text)
  (eval (read-from-string text))
  (fresh-line))

(define-command say (irc text)
  (when (and (irc-connection irc) (current-channel irc))
    (format t "[~A]<~A> ~A~%" (current-channel irc) (nickname irc) text)
    (send (irc-connection irc) "PRIVMSG ~A :~A~%"
          (current-channel irc) text)))

(define-command me (irc text)
  (when (and (irc-connection irc) (current-channel irc))
    (format t "[~A]* ~A ~A~%" (current-channel irc) (nickname irc) text)
    (send (irc-connection irc) "PRIVMSG ~A :~AACTION ~A~A~%"
          (current-channel irc) (code-char 1) text (code-char 1))))

(define-command nick (irc text)
  (format t "Changing nickname to ~A.~%" text)
  (setf (nickname irc) text)
  (when (irc-connection irc)
    (send (irc-connection irc) "NICK ~A~%" (nickname irc))))

(define-command connect (irc text)
  (cond ((not (nickname irc))
         (format t "Use /nick to set a nickname before connecting.~%"))
        ((irc-connection irc)
         (format t "Already connected.~%"))
        (t (multiple-value-bind (address port)
               (resolve-server-name text)
             (setf (irc-connection irc) (sys.net::tcp-stream-connect address port))
             (send (irc-connection irc) "USER ~A hostname servername :~A~%" (nickname irc) (nickname irc))
             (send (irc-connection irc) "NICK ~A~%" (nickname irc))))))

(define-command join (irc text)
  (if (find text (joined-channels irc) :test 'equal)
      (format t "Already joined to ~A.~%" text)
      (when (irc-connection irc)
        (send (irc-connection irc) "JOIN ~A~%" text)
        (push text (joined-channels irc))
        (unless (current-channel irc)
          (setf (current-channel irc) text)))))

(define-command chan (irc text)
  (when (irc-connection irc)
    (if (find text (joined-channels irc) :test 'equal)
        (setf (current-channel irc) text)
        (format t "Not joined to channel ~A." text))))

(define-command part (irc text)
  (when (and (irc-connection irc) (current-channel irc))
    (send (irc-connection irc) "PART ~A :~A~%" (current-channel irc) text)
    (setf (joined-channels irc) (remove (current-channel irc) (joined-channels irc)))
    (setf (current-channel irc) (first (joined-channels irc)))))

(defun irc-top-level (irc)
  (let ((*standard-input* irc)
        (*standard-output* (irc-display irc))
        (*error-output* (irc-display irc))
        (*query-io* (make-two-way-stream irc (irc-display irc)))
        (*debug-io* (make-two-way-stream irc (irc-display irc))))
    (unwind-protect
         (handler-case
             (loop (format irc "~A] " (or (current-channel irc) "")) ; write prompt to the input line. (ugh!)
                (let ((line (read-line)))
                  (sys.int::stream-move-to irc 0 0)
                  (cond ((and (>= (length line) 1)
                              (eql (char line 0) #\/)
                              (not (and (>= (length line) 2)
                                        (eql (char line 1) #\/))))
                         (multiple-value-bind (command rest)
                             (parse-command line)
                           (let ((fn (gethash (string-upcase command) *top-level-commands*)))
                             (if fn
                                 (with-simple-restart (abort "Abort evaulation and return to IRC.")
                                   (funcall fn irc rest))
                                 (format t "Unknown command ~S.~%" command)))))
                        ((current-channel irc)
                         (format t "[~A]<~A> ~A~%" (current-channel irc) (nickname irc) line)
                         (send (irc-connection irc) "PRIVMSG ~A :~A~%" (current-channel irc) line)))))
           (quit-irc ()))
      (sys.int::process-disable (irc-receive-process irc))
      (when (irc-connection irc)
        (close (irc-connection irc)))
      (sys.graphics::close-window irc))))

(defun create-irc-client ()
  "Open an IRC window."
  (sys.graphics::window-set-visibility (sys.graphics::make-window "IRC" 640 400 'irc-client) t))

(setf (gethash (name-char "F2") sys.graphics::*global-keybindings*) 'create-irc-client)
