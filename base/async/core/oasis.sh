#!/usr/bin/env bash
set -e -u -o pipefail

source ../../../build-common.sh

cat >$HERE/_oasis <<EOF
#AUTOGENERATED FILE; EDIT oasis.sh INSTEAD

OASISFormat:  0.3
OCamlVersion: >= 3.12.1
Name:         async_core
Version:      $core_version
Synopsis:     Jane Street Capital's asynchronous execution library (core)
Authors:      Jane street capital
Copyrights:   (C) 2008-2012 Jane Street Capital LLC
License:      LGPL-2.1 with OCaml linking exception
LicenseFile:  LICENSE
Plugins:      StdFiles (0.3), DevFiles (0.3), META (0.3)
BuildTools:   ocamlbuild
Description:  Jane Street Capital's asynchronous execution library
FindlibVersion: >= 1.2.7
XStdFilesAUTHORS: false
XStdFilesINSTALLFilename: INSTALL
XStdFilesREADME: false

Library async_core
  Path:               lib
  FindlibName:        async_core
  Pack:               true
  Modules:            $(list_mods "$HERE/lib")
  BuildDepends:       sexplib.syntax,
                      sexplib,
                      pa_ounit,
                      fieldslib.syntax,
                      fieldslib,
                      bin_prot,
                      bin_prot.syntax,
                      core,
                      threads

EOF

make_tags "$HERE/_tags" <<EOF
<lib/*.ml{,i}>: syntax_camlp4o
EOF

make_myocamlbuild_default "$HERE/myocamlbuild.ml"

cd $HERE
rm -f setup.ml
oasis setup
