;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2018 Mathieu Othacehe <m.othacehe@gmail.com>
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

(define-module (gnu installer)
  #:use-module (guix discovery)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix modules)
  #:use-module (guix utils)
  #:use-module (guix ui)
  #:use-module ((guix self) #:select (make-config.scm))
  #:use-module (gnu packages admin)
  #:use-module (gnu packages base)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages connman)
  #:use-module (gnu packages disk)
  #:use-module (gnu packages guile)
  #:autoload   (gnu packages gnupg) (guile-gcrypt)
  #:use-module (gnu packages iso-codes)
  #:use-module (gnu packages linux)
  #:use-module (gnu packages ncurses)
  #:use-module (gnu packages package-management)
  #:use-module (gnu packages xorg)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:export (installer-program))

(define not-config?
  ;; Select (guix …) and (gnu …) modules, except (guix config).
  (match-lambda
    (('guix 'config) #f)
    (('guix rest ...) #t)
    (('gnu rest ...) #t)
    (rest #f)))

(define* (build-compiled-file name locale-builder)
  "Return a file-like object that evalutes the gexp LOCALE-BUILDER and store
its result in the scheme file NAME. The derivation will also build a compiled
version of this file."
  (define set-utf8-locale
    #~(begin
        (setenv "LOCPATH"
                #$(file-append glibc-utf8-locales "/lib/locale/"
                               (version-major+minor
                                (package-version glibc-utf8-locales))))
        (setlocale LC_ALL "en_US.utf8")))

  (define builder
    (with-extensions (list guile-json)
      (with-imported-modules (source-module-closure
                              '((gnu installer locale)))
        #~(begin
            (use-modules (gnu installer locale))

            ;; The locale files contain non-ASCII characters.
            #$set-utf8-locale

            (mkdir #$output)
            (let ((locale-file
                   (string-append #$output "/" #$name ".scm"))
                  (locale-compiled-file
                   (string-append #$output "/" #$name ".go")))
              (call-with-output-file locale-file
                (lambda (port)
                  (write #$locale-builder port)))
              (compile-file locale-file
                            #:output-file locale-compiled-file))))))
  (computed-file name builder))

(define apply-locale
  ;; Install the specified locale.
  #~(lambda (locale-name)
      (false-if-exception
       (setlocale LC_ALL locale-name))))

(define* (compute-locale-step #:key
                              locales-name
                              iso639-languages-name
                              iso3166-territories-name)
  "Return a gexp that run the locale-page of INSTALLER, and install the
selected locale. The list of locales, languages and territories passed to
locale-page are computed in derivations named respectively LOCALES-NAME,
ISO639-LANGUAGES-NAME and ISO3166-TERRITORIES-NAME. Those lists are compiled,
so that when the installer is run, all the lengthy operations have already
been performed at build time."
  (define (compiled-file-loader file name)
    #~(load-compiled
       (string-append #$file "/" #$name ".go")))

  (let* ((supported-locales #~(supported-locales->locales
                               #$(local-file "installer/aux-files/SUPPORTED")))
         (iso-codes #~(string-append #$iso-codes "/share/iso-codes/json/"))
         (iso639-3 #~(string-append #$iso-codes "iso_639-3.json"))
         (iso639-5 #~(string-append #$iso-codes "iso_639-5.json"))
         (iso3166 #~(string-append #$iso-codes "iso_3166-1.json"))
         (locales-file (build-compiled-file
                        locales-name
                        #~`(quote ,#$supported-locales)))
         (iso639-file (build-compiled-file
                       iso639-languages-name
                       #~`(quote ,(iso639->iso639-languages
                                   #$supported-locales
                                   #$iso639-3 #$iso639-5))))
         (iso3166-file (build-compiled-file
                        iso3166-territories-name
                        #~`(quote ,(iso3166->iso3166-territories #$iso3166))))
         (locales-loader (compiled-file-loader locales-file
                                               locales-name))
         (iso639-loader (compiled-file-loader iso639-file
                                              iso639-languages-name))
         (iso3166-loader (compiled-file-loader iso3166-file
                                               iso3166-territories-name)))
    #~(lambda (current-installer)
        (let ((result
               ((installer-locale-page current-installer)
                #:supported-locales #$locales-loader
                #:iso639-languages #$iso639-loader
                #:iso3166-territories #$iso3166-loader)))
          (#$apply-locale result)
          result))))

(define apply-keymap
  ;; Apply the specified keymap. Use the default keyboard model.
  #~(match-lambda
      ((layout variant)
       (kmscon-update-keymap (default-keyboard-model)
                             layout variant))))

(define* (compute-keymap-step)
  "Return a gexp that runs the keymap-page of INSTALLER and install the
selected keymap."
  #~(lambda (current-installer)
      (let ((result
             (call-with-values
                 (lambda ()
                   (xkb-rules->models+layouts
                    (string-append #$xkeyboard-config
                                   "/share/X11/xkb/rules/base.xml")))
               (lambda (models layouts)
                 ((installer-keymap-page current-installer)
                  layouts)))))
        (#$apply-keymap result))))

(define (installer-steps)
  (let ((locale-step (compute-locale-step
                      #:locales-name "locales"
                      #:iso639-languages-name "iso639-languages"
                      #:iso3166-territories-name "iso3166-territories"))
        (keymap-step (compute-keymap-step))
        (timezone-data #~(string-append #$tzdata
                                        "/share/zoneinfo/zone.tab")))
    #~(lambda (current-installer)
        (list
         ;; Welcome the user and ask him to choose between manual
         ;; installation and graphical install.
         (installer-step
          (id 'welcome)
          (compute (lambda _
                     ((installer-welcome-page current-installer)
                      #$(local-file "installer/aux-files/logo.txt")))))

         ;; Ask the user to choose a locale among those supported by
         ;; the glibc.  Install the selected locale right away, so that
         ;; the user may benefit from any available translation for the
         ;; installer messages.
         (installer-step
          (id 'locale)
          (description (G_ "Locale"))
          (compute (lambda _
                     (#$locale-step current-installer)))
          (configuration-formatter locale->configuration))

         ;; Ask the user to select a timezone under glibc format.
         (installer-step
          (id 'timezone)
          (description (G_ "Timezone"))
          (compute (lambda _
                     ((installer-timezone-page current-installer)
                      #$timezone-data)))
          (configuration-formatter posix-tz->configuration))

         ;; The installer runs in a kmscon virtual terminal where loadkeys
         ;; won't work. kmscon uses libxkbcommon as a backend for keyboard
         ;; input. It is possible to update kmscon current keymap by sending it
         ;; a keyboard model, layout and variant, in a somehow similar way as
         ;; what is done with setxkbmap utility.
         ;;
         ;; So ask for a keyboard model, layout and variant to update the
         ;; current kmscon keymap.
         (installer-step
          (id 'keymap)
          (description (G_ "Keyboard mapping selection"))
          (compute (lambda _
                     (#$keymap-step current-installer))))

         ;; Run a partitionment tool allowing the user to modify
         ;; partition tables, partitions and their mount points.
         (installer-step
          (id 'partition)
          (description (G_ "Partitionment"))
          (compute (lambda _
                     ((installer-partition-page current-installer))))
          (configuration-formatter user-partitions->configuration))

         ;; Ask the user to input a hostname for the system.
         (installer-step
          (id 'hostname)
          (description (G_ "Hostname"))
          (compute (lambda _
                     ((installer-hostname-page current-installer))))
          (configuration-formatter hostname->configuration))

         ;; Provide an interface above connmanctl, so that the user can select
         ;; a network susceptible to acces Internet.
         (installer-step
          (id 'network)
          (description (G_ "Network selection"))
          (compute (lambda _
                     ((installer-network-page current-installer)))))

         ;; Prompt for users (name, group and home directory).
         (installer-step
          (id 'user)
          (description (G_ "User creation"))
          (compute (lambda _
                     ((installer-user-page current-installer))))
          (configuration-formatter users->configuration))

         ;; Ask the user to choose one or many desktop environment(s).
         (installer-step
          (id 'services)
          (description (G_ "Services"))
          (compute (lambda _
                     ((installer-services-page current-installer))))
	  (configuration-formatter
           desktop-environments->configuration))

	 (installer-step
          (id 'final)
          (description (G_ "Configuration file"))
          (compute
           (lambda (result prev-steps)
             ((installer-final-page current-installer)
              result prev-steps))))))))

(define (installer-program)
  "Return a file-like object that runs the given INSTALLER."
  (define init-gettext
    ;; Initialize gettext support, so that installer messages can be
    ;; translated.
    #~(begin
        (bindtextdomain "guix" (string-append #$guix "/share/locale"))
        (textdomain "guix")))

  (define set-installer-path
    ;; Add the specified binary to PATH for later use by the installer.
    #~(let* ((inputs
              '#$(append (list bash ;start subshells
                               connman ;call connmanctl
                               dosfstools ;mkfs.fat
                               e2fsprogs ;mkfs.ext4
                               kbd ;chvt
                               guix ;guix system init call
                               util-linux ;mkwap
                               shadow)
                         (map canonical-package (list coreutils)))))
        (with-output-to-port (%make-void-port "w")
          (lambda ()
            (set-path-environment-variable "PATH" '("bin" "sbin") inputs)))))

  (define steps (installer-steps))
  (define modules
    (scheme-modules*
     (string-append (current-source-directory) "/..")
     "gnu/installer"))

  (define installer-builder
    (with-extensions (list guile-gcrypt guile-newt
                           guile-parted guile-bytestructures
                           guile-json)
      (with-imported-modules `(,@(source-module-closure
                                  `(,@modules
                                    (guix build utils))
                                  #:select? not-config?)
                               ((guix config) => ,(make-config.scm)))
        #~(begin
            (use-modules (gnu installer record)
                         (gnu installer keymap)
                         (gnu installer steps)
                         (gnu installer final)
                         (gnu installer hostname)
                         (gnu installer locale)
                         (gnu installer parted)
                         (gnu installer services)
                         (gnu installer timezone)
                         (gnu installer user)
                         (gnu installer newt)
                         (guix i18n)
                         (guix build utils)
                         (ice-9 match))

            ;; Initialize gettext support so that installers can use
            ;; (guix i18n) module.
            #$init-gettext

            ;; Add some binaries used by the installers to PATH.
            #$set-installer-path

            (let* ((current-installer newt-installer)
                   (steps (#$steps current-installer)))
              ((installer-init current-installer))

              (catch #t
                (lambda ()
                  (run-installer-steps
                   #:rewind-strategy 'menu
                   #:menu-proc (installer-menu-page current-installer)
                   #:steps steps))
                (const #f)
                (lambda (key . args)
                  (let ((error-file "/tmp/last-installer-error"))
                    (call-with-output-file error-file
                      (lambda (port)
                        (display-backtrace (make-stack #t) port)
                        (print-exception port
                                         (stack-ref (make-stack #t) 1)
                                         key args)))
                    ((installer-exit-error current-installer)
                     error-file key args))
                  (primitive-exit 1)))

              ((installer-exit current-installer)))))))

  (program-file
   "installer"
   #~(begin
       ;; Set the default locale to install unicode support.  For
       ;; some reason, unicode support is not correctly installed
       ;; when calling this in 'installer-builder'.
       (setenv "LANG" "en_US.UTF-8")
       (system #$(program-file "installer-real" installer-builder)))))