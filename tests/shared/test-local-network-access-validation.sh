#!/usr/bin/env bash
# localNetworkAccess.darwinAllowedTargets must fail at eval time for values
# that macOS Seatbelt cannot parse. sandbox-exec only accepts localhost-style
# host selectors in (remote ip ...); arbitrary LAN/VM IPs otherwise fail at
# runtime with "host must be * or localhost in network address".
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

eval_with_target() {
	local target="$1"
	nix-instantiate --eval -I nixpkgs=flake:nixpkgs -E "
    let
      pkgs = import <nixpkgs> { };
      sandbox = import ${REPO_ROOT}/default.nix { inherit pkgs; };
      wrapper = sandbox.mkSandbox {
        pkg = pkgs.bashInteractive;
        binName = \"bash\";
        outName = \"local-network-validation-test\";
        allowedPackages = [ pkgs.coreutils ];
        localNetworkAccess = {
          enable = true;
          darwinAllowedTargets = [ \"${target}\" ];
        };
      };
    in builtins.seq wrapper \"ok\"
  " 2>&1
}

render_darwin_rules_with_target() {
	local target="$1"
	nix-instantiate --eval --raw -I nixpkgs=flake:nixpkgs -E "
    let
      pkgs = import <nixpkgs> { };
      shared = import ${REPO_ROOT}/lib/shared.nix { inherit pkgs; };
      networking = import ${REPO_ROOT}/lib/darwin/networking.nix {
        inherit pkgs shared;
        allowedDomains = null;
        localNetworkAccess = shared.validateLocalNetworkAccess {
          enable = true;
          darwinAllowedTargets = [ \"${target}\" ];
        };
      };
    in networking.networkSeatbeltRulesStr
  " 2>&1
}

expect_ok_target() {
	local desc="$1" target="$2"
	local out
	if out=$(eval_with_target "$target"); then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc (eval failed)"
		printf '%s\n' "$out" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
	fi
}

expect_invalid_target() {
	local desc="$1" target="$2" needle="$3"
	local out
	if out=$(eval_with_target "$target"); then
		echo "FAIL: $desc (eval succeeded; expected validation error)"
		FAIL=$((FAIL + 1))
	elif printf '%s' "$out" | grep -qF "$needle"; then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc (threw, but message missing: $needle)"
		printf '%s\n' "$out" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
	fi
}

expect_normalized_target() {
	local desc="$1" target="$2" expected="$3" unexpected="$4"
	local out
	if ! out=$(render_darwin_rules_with_target "$target"); then
		echo "FAIL: $desc (render failed)"
		printf '%s\n' "$out" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
	elif ! printf '%s' "$out" | grep -qF "$expected"; then
		echo "FAIL: $desc (missing expected rule: $expected)"
		printf '%s\n' "$out" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
	elif [ -n "$unexpected" ] && printf '%s' "$out" | grep -qF "$unexpected"; then
		echo "FAIL: $desc (found unnormalized rule: $unexpected)"
		printf '%s\n' "$out" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
	else
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	fi
}

echo "=== localNetworkAccess validation ==="
echo

expect_ok_target "localhost target is accepted" "localhost:3000"
expect_ok_target "IPv4 loopback alias is accepted for compatibility" "127.0.0.1:3000"
expect_ok_target "IPv6 loopback alias is accepted for compatibility" "[::1]:3000"
expect_invalid_target "non-loopback VM/LAN IP is rejected before sandbox-exec" \
	"10.254.254.1:*" \
	"Darwin sandbox-exec only supports localhost-style localNetworkAccess targets"
expect_normalized_target "IPv4 loopback alias is emitted as sandbox-exec-compatible localhost" \
	"127.0.0.1:3000" \
	'(allow network-outbound (remote ip "localhost:3000"))' \
	'(allow network-outbound (remote ip "127.0.0.1:3000"))'

print_results
exit_status
