#!/usr/bin/env bash
# localNetworkAccess.darwinAllowedTargets must fail before sandbox-exec for
# values that macOS Seatbelt cannot parse. sandbox-exec only accepts
# localhost-style host selectors in (remote ip ...); arbitrary LAN/VM IPs
# otherwise fail at runtime with "host must be * or localhost in network address".
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

build_with_target() {
	local target="$1"
	nix-build --no-out-link --argstr target "$target" "$SCRIPT_DIR/../fixtures/network-local-access-darwin.nix" 2>&1
}

sandbox_profile_for_wrapper() {
	local wrapper="$1/bin/sandboxed-bash-local-access"
	grep -Eo '/nix/store/[^" ]+-sandboxed-bash-local-access-sandbox\.sb' "$wrapper" | head -n 1
}

expect_ok_target() {
	local desc="$1" target="$2"
	local out
	if out=$(build_with_target "$target"); then
		echo "PASS: $desc"
		PASS=$((PASS + 1))
	else
		echo "FAIL: $desc (build failed)"
		printf '%s\n' "$out" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
	fi
}

expect_invalid_target() {
	local desc="$1" target="$2" needle="$3"
	local out
	if out=$(build_with_target "$target"); then
		echo "FAIL: $desc (build succeeded; expected validation error)"
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
	local out profile
	if ! out=$(build_with_target "$target"); then
		echo "FAIL: $desc (build failed)"
		printf '%s\n' "$out" | sed 's/^/    /'
		FAIL=$((FAIL + 1))
	elif ! profile=$(sandbox_profile_for_wrapper "$out"); then
		echo "FAIL: $desc (sandbox profile not found)"
		FAIL=$((FAIL + 1))
	elif ! grep -qF "$expected" "$profile"; then
		echo "FAIL: $desc (missing expected rule: $expected)"
		sed 's/^/    /' "$profile"
		FAIL=$((FAIL + 1))
	elif [ -n "$unexpected" ] && grep -qF "$unexpected" "$profile"; then
		echo "FAIL: $desc (found unnormalized rule: $unexpected)"
		sed 's/^/    /' "$profile"
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
