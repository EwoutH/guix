;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2013 Nikita Karetnikov <nikita@karetnikov.org>
;;; Copyright © 2014, 2015 Mark H Weaver <mhw@netris.org>
;;; Copyright © 2017 Efraim Flashner <efraim@flashner.co.il>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (gnu packages apl)
  #:use-module (guix licenses)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system gnu)
  #:use-module (gnu packages gettext)
  #:use-module (gnu packages maths)
  #:use-module (gnu packages readline)
  #:use-module (gnu packages sqlite))

(define-public apl
  (package
    (name "apl")
    (version "1.7")
    (source
     (origin
      (method url-fetch)
      (uri (string-append "mirror://gnu/apl/apl-" version ".tar.gz"))
      (sha256
       (base32
        "07xq8ddlmz8psvsmwr23gar108ri0lwmw0n6kpxcv8ypas1f5xlg"))))
    (build-system gnu-build-system)
    (home-page "https://www.gnu.org/software/apl/")
    (inputs
     `(("gettext" ,gettext-minimal)
       ("lapack" ,lapack)
       ("sqlite" ,sqlite)
       ("readline" ,readline)))
    (arguments
     `(#:configure-flags (list (string-append
                                "--with-sqlite3="
                                (assoc-ref %build-inputs "sqlite")))))
    (synopsis "APL interpreter")
    (description
     "GNU APL is a free interpreter for the programming language APL.  It is
an implementation of the ISO standard 13751.")
    (license gpl3+)))
