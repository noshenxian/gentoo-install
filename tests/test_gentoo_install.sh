#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/gentoo-install.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

assert_contains() {
    local haystack="$1" needle="$2" message="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$message: missing '$needle'"
}

LIB_ONLY=1 source "$SCRIPT"

test_parse_latest_stage3_file_ignores_pgp_lines() {
    local latest_file="$TMPDIR/latest-stage3.txt"
    cat > "$latest_file" <<'EOF'
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA256

# Latest as of Tue, 28 Apr 2026 21:00:00 +0000
stage3-amd64-desktop-systemd-20260426T153103Z.tar.xz 800172308
-----BEGIN PGP SIGNATURE-----
abc
-----END PGP SIGNATURE-----
EOF

    local parsed
    parsed="$(parse_latest_stage3_file "$latest_file")"
    assert_eq "stage3-amd64-desktop-systemd-20260426T153103Z.tar.xz" "$parsed" "latest stage3 parser"
}

test_parse_digest_hash_finds_sha512_hash() {
    local digests_file="$TMPDIR/stage3.DIGESTS"
    cat > "$digests_file" <<'EOF'
# SHA512 HASH
SHA512 HASH stage3-amd64-desktop-systemd-20260426T153103Z.tar.xz
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  stage3-amd64-desktop-systemd-20260426T153103Z.tar.xz
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  stage3-amd64-desktop-systemd-20260426T153103Z.tar.xz.CONTENTS.gz
EOF

    local parsed
    parsed="$(parse_sha512_digest "$digests_file" "stage3-amd64-desktop-systemd-20260426T153103Z.tar.xz")"
    assert_eq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$parsed" "sha512 digest parser"
}

test_validate_config_rejects_bad_root_fs_before_install() {
    INIT_SYSTEM="systemd"
    ROOT_FS="zfs"
    DISK="/dev/null"
    EFI_SIZE=512
    SWAP_SIZE=4096

    if validate_config >/tmp/validate.out 2>&1; then
        fail "validate_config should reject unsupported ROOT_FS"
    fi
}

test_config_dry_run_shows_requested_config() {
    local config_file="$TMPDIR/custom.conf"
    cat > "$config_file" <<'EOF'
INIT_SYSTEM="openrc"
DISK="/dev/testdisk"
EFI_SIZE=512
SWAP_SIZE=4096
ROOT_FS="xfs"
HOSTNAME="from-custom-config"
TIMEZONE="Asia/Tokyo"
DOMAIN="local"
ROOT_PASSWORD="rootpw"
USERNAME="alice"
USER_PASSWORD="userpw"
ADD_SUDO="no"
USE_BINARY_PACKAGES="no"
EOF

    local output
    output="$(bash "$SCRIPT" -c "$config_file" --dry-run)"
    assert_contains "$output" "HOSTNAME=\"from-custom-config\"" "dry-run should show requested config"
    assert_contains "$output" "配置文件: $config_file" "dry-run should identify requested config"
}

test_write_binrepos_conf_uses_sync_uri() {
    local root="$TMPDIR/root"
    mkdir -p "$root"
    BINHOST_USTC="https://mirrors.ustc.edu.cn/gentoo/releases/amd64/binpackages/23.0/x86-64/"

    write_binrepos_conf "$root"

    local conf="$root/etc/portage/binrepos.conf/gentoobinhost.conf"
    [[ -f "$conf" ]] || fail "binrepos config should be created"
    local content
    content="$(cat "$conf")"
    assert_contains "$content" "[binhost]" "binrepos should define binhost"
    assert_contains "$content" "sync-uri = https://mirrors.ustc.edu.cn/gentoo/releases/amd64/binpackages/23.0/x86-64/" "binrepos should use sync-uri"
}

test_parse_latest_stage3_file_ignores_pgp_lines
test_parse_digest_hash_finds_sha512_hash
test_validate_config_rejects_bad_root_fs_before_install
test_config_dry_run_shows_requested_config
test_write_binrepos_conf_uses_sync_uri

echo "All tests passed"
