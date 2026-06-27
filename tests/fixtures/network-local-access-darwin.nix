# Test fixture: Darwin open-network sandbox with one explicit local-network
# target allowlisted. Used to assert localNetworkAccess opt-in is narrow.
{ target ? "localhost:18934" }:
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash-local-access";
  allowedPackages = [ pkgs.coreutils pkgs.curl ];
  localNetworkAccess = {
    enable = true;
    darwinAllowedTargets = [ target ];
  };
}
