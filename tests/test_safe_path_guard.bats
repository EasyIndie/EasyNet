#!/usr/bin/env bats
# Regression guard for the rm -rf safety checks added for install.sh / deploy.sh.
# An operator mis-setting EASYNET_INSTALL_DIR or EASYNET_STATE_DIR to a
# filesystem-critical path must never reach rm -rf.

load test_helper

setup() {
    DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    PROJECT_ROOT="$(cd "$DIR/.." && pwd)"
    source "$PROJECT_ROOT/scripts/core/env.sh"
}

@test "easynet_assert_safe_rm_path accepts the default state dir" {
    run easynet_assert_safe_rm_path "/var/lib/easynet"
    [ "$status" -eq 0 ]
}

@test "easynet_assert_safe_rm_path accepts a deep /opt path" {
    run easynet_assert_safe_rm_path "/opt/easynet"
    [ "$status" -eq 0 ]
}

@test "easynet_assert_safe_rm_path rejects filesystem root" {
    run easynet_assert_safe_rm_path "/"
    [ "$status" -eq 1 ]
}

@test "easynet_assert_safe_rm_path rejects critical top-level dirs" {
    local p
    for p in /bin /sbin /lib /lib64 /boot /etc /usr /var /home /root /opt /srv /proc /sys /dev /run /tmp /mnt /media; do
        run easynet_assert_safe_rm_path "$p"
        [ "$status" -eq 1 ]
    done
}

@test "easynet_assert_safe_rm_path rejects empty and relative paths" {
    run easynet_assert_safe_rm_path ""
    [ "$status" -eq 1 ]
    run easynet_assert_safe_rm_path "relative/path"
    [ "$status" -eq 1 ]
}

@test "install.sh assert_safe_install_dir rejects / and accepts /opt/easynet" {
    run_function "$PROJECT_ROOT/scripts/install.sh" assert_safe_install_dir "/opt/easynet"
    [ "$status" -eq 0 ]

    run_function "$PROJECT_ROOT/scripts/install.sh" assert_safe_install_dir "/"
    [ "$status" -eq 1 ]

    run_function "$PROJECT_ROOT/scripts/install.sh" assert_safe_install_dir "/etc"
    [ "$status" -eq 1 ]

    run_function "$PROJECT_ROOT/scripts/install.sh" assert_safe_install_dir ""
    [ "$status" -eq 1 ]
}
