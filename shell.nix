let
  pkgs = import <nixpkgs> {};
in with pkgs;
mkShell {

  TCLLIBPATH = "${tcllib}/lib/tcllib1.19";
  buildInputs = [ tcl-8_6 tcllib coreutils ];
}
