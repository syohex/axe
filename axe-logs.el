;;; axe-logs.el --- Functions for working with AWS logs -*- lexical-binding: t; -*-

;; Copyright (C) 2020 Craig Niles

;; Author: Craig Niles <niles.c at gmail.com>
;; Maintainer: Craig Niles <niles.c at gmail.com>
;; URL: https://github.com/cniles/axe

;; This file is NOT part of GNU Emacs.

;; axe is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; axe is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with axe.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; axe-logs.el provides functions for viewing AWS CloudWatch Logs
;; log-groups, streams and stream events.

;;; Code:

(require 'json)
(require 'thingatpt)
(require 'axe-api)
(require 'axe-util)
(require 'axe-buffer-mode)

(cl-defun axe-logs--describe-log-groups (success &key next-token prefix limit)
  "Request log groups using PREFIX and NEXT-TOKEN.

Provide results to callback function SUCCESS on comletion.  Both
can be specified nil to omit."
  (axe-api-request
   (axe-api-domain 'logs axe-region)
   'logs
   success
   "POST"
   :parser #'json-read
   :headers '(("Content-Type" . "application/x-amz-json-1.1")
	      ("X-Amz-Target" . "Logs_20140328.DescribeLogGroups"))
   :request-payload (axe-util--trim-and-encode-alist
		     (list (cons "limit" limit)
			   (cons "nextToken" next-token)
			   (cons "logGroupNamePrefix" prefix)))))

(cl-defun axe-logs--describe-log-streams (success log-group-name &key next-token descending limit log-stream-name-prefix order-by)
  "Describe log streams for LOG-GROUP-NAME."
  (axe-api-request
   (axe-api-domain 'logs axe-region)
   'logs
   success
   "POST"
   :parser #'json-read
   :headers '(("Content-Type" . "application/x-amz-json-1.1")
	      ("X-Amz-Target" . "Logs_20140328.DescribeLogStreams"))
   :request-payload (axe-util--trim-and-encode-alist
		     (list (cons "logGroupName" log-group-name)
			   (cons "descending" descending)
			   (cons "limit" limit)
			   (cons "logStreamNamePrefix" log-stream-name-prefix)
			   (cons "nextToken" next-token)
			   (cons "orderBy" order-by)))))

(cl-defun axe-logs--get-log-events (success log-group-name log-stream-name &key next-token end-time limit start-from-head start-time)
  "Get log events for stream with name LOG-STREAM-NAME of group LOG-GROUP-NAME"
  (axe-api-request
   (axe-api-domain 'logs axe-region)
   'logs
   success
   "POST"
   :parser #'json-read
   :headers '(("Content-Type" . "application/x-amz-json-1.1")
	      ("X-Amz-Target" . "Logs_20140328.GetLogEvents"))
   :request-payload (axe-util--trim-and-encode-alist
		     (list (cons "logGroupName" log-group-name)
			   (cons "logStreamName" log-stream-name)
			   (cons "nextToken" next-token)
			   (cons "endTime" end-time)
			   (cons "limit" limit)
			   (cons "startFromHead" start-from-head)
			   (cons "startTime" start-time)))))

;;; Insert functions

(cl-defun axe-logs--insert-log-group (log-group &key &allow-other-keys)
  "Insert formatted text for LOG-GROUP into current buffer."
  (let ((inhibit-read-only t)
	(log-group-name (alist-get 'logGroupName log-group))
	(size (file-size-human-readable (alist-get 'storedBytes log-group)))
	(creation-time (format-time-string "%F %T" (seconds-to-time (/ (alist-get 'creationTime log-group) 1000)))))
    (insert (propertize (format "%s %8s %s\n" creation-time size log-group-name) 'log-group log-group))))

(cl-defun axe-logs--insert-log-event (log-event &key &allow-other-keys)
  "Insert formatted text for LOG-EVENT into current buffer."
  (let ((inhibit-read-only t)
	(message (alist-get 'message log-event))
	(timestamp (format-time-string "%F %T" (seconds-to-time (/ (alist-get 'timestamp log-event) 1000)))))
    (insert (propertize (format "%s %s\n" timestamp message) 'log-event log-event))))

;;; List buffers

;;;###autoload
(defun axe-logs-describe-log-groups (prefix)
  "Opens a new buffer and displays all log groups.
If PREFIX is not nil, it is used to filter by log group name
prefix.  May result in multiple API calls.  If that is the case
then subsequent results may take some time to load and
displayed."
  (interactive "sPrefix: ")
  (let ((prefix (if (equal "" prefix) nil prefix))
	(limit ()))
    (axe-buffer-list
     #'axe-logs--describe-log-groups
     "*axe-log-groups*"
     (cl-function (lambda (&key data &allow-other-keys)
		    (alist-get 'logGroups data)))
     (list :prefix prefix :limit limit)
     (lambda (map)
       (define-key map (kbd "l") #'axe-logs-latest-log-stream-at-point)
       map)
     #'axe-logs--insert-log-group
     (cl-function (lambda (&key data &allow-other-keys)
		    (alist-get 'nextToken data)))
     :auto-follow t
     :auto-follow-delay 0.1)))

;;;###autoload
(cl-defun axe-logs-get-log-events (log-group-name log-stream-name &key auto-follow (auto-follow-delay 5.0))
  "Display log events for stream with name LOG-STREAM-NAME in log group LOG-GROUP-NAME.
Specifying FOLLOW-NEXT as non-nil will start the buffer in follow
mode.  In follow mode the next API request will automatically be
executed after FOLLOW-DELAY seconds (default 5 seconds)."
  (interactive "sLog Group Name:
sLog Stream Name: ")
  (axe-buffer-list
   #'axe-logs--get-log-events
   (format "*axe-log-stream:%s*" log-stream-name)
   (cl-function (lambda (&key data &allow-other-keys) (alist-get 'events data)))
   (list log-group-name log-stream-name)
   ()
   #'axe-logs--insert-log-event
   (cl-function (lambda (&key data &allow-other-keys)
     (alist-get 'nextForwardToken data)))
   :auto-follow auto-follow
   :auto-follow-delay auto-follow-delay))

(defun axe-logs--log-group-name-at-point ()
  "Get the log group name at point."
  (let ((log-group (get-text-property (point) 'log-group)))
    (if (null log-group) (thing-at-point 'symbol) (alist-get 'logGroupName log-group))))

;;;###autoload
(defun axe-logs-latest-log-stream-at-point ()
  "Open the log stream defined at the current  point.
First checks for text property log-group otherwise uses the text
at point in the buffer."
  (interactive)
  (let ((log-group-name (axe-logs--log-group-name-at-point)))
    (axe-logs--describe-log-streams
     (cl-function
      (lambda (&key data &allow-other-keys)
	(let ((log-stream-name (alist-get 'logStreamName (elt (alist-get 'logStreams data) 0))))
	  (axe-logs-get-log-events log-group-name log-stream-name))))
     log-group-name
     :limit 1
     :descending t
     :order-by "LastEventTime")))

(provide 'axe-logs)
;;; axe-logs.el ends here
