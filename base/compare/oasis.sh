#!/usr/bin/env bash
set -e -u -o pipefail

source ../../build-common.sh

cat >$HERE/_oasis <<EOF
#AUTOGENERATED FILE; EDIT oasis.sh INSTEAD
OASISFormat:  0.3
OCamlVersion: >= 3.12.1
Name:         comparelib
Version:      $core_version
Synopsis:     Syntax extension for deriving "compare" functions automatically.
Authors:      Jane street capital
Copyrights:   (C) 2009-2011 Jane Street Capital LLC
License:      LGPL-2.1 with OCaml linking exception
LicenseFile:  LICENSE
Plugins:      StdFiles (0.3), DevFiles (0.3), META (0.3)
XStdFilesREADME: false
XStdFilesAUTHORS: false
XStdFilesINSTALLFilename: INSTALL
BuildTools:   ocamlbuild

Library comparelib
  Path:               lib
  Modules:            Comparelib_dummy
  FindlibName:        comparelib
  XMETAType:          library

Library pa_compare
  Path:               syntax
  Modules:            Pa_compare
  FindlibParent:      comparelib
  FindlibName:        syntax
  BuildDepends:       camlp4.lib,
                      camlp4.quotations,
                      type_conv (>= 3.0.5)
  CompiledObject:     byte
  XMETAType:          syntax
  XMETARequires:      camlp4,type_conv,comparelib
  XMETADescription:   Syntax extension for "with compare"
EOF

make_tags $HERE/_tags <<EOF
<syntax/pa_compare.ml>: syntax_camlp4o
EOF

make_myocamlbuild_default "$HERE/myocamlbuild.ml"

mkdir -p $HERE/lib
echo >$HERE/lib/comparelib_dummy.ml

cd $HERE
oasis setup
