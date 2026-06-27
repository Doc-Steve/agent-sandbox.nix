# Test fixture: open-network sandbox with one explicit host-loopback target
# allowlisted. Used to assert localNetworkAccess opt-in is narrow.
{ target ? "localhost:18934" }:
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash-local-access";
  allowedPackages = [ pkgs.coreutils pkgs.curl pkgs.python3Minimal ];
  localNetworkAccess = {
    enable = true;
    allowedTargets = [ target ];
  };
}
