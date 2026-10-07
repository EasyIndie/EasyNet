use std::ffi::{c_char, c_int, c_void};

pub type Vault = c_void;
#[repr(C)]
#[derive(Clone, Copy)]
pub struct VaultProbe {
    pub path_guard_ok: bool,
    pub stage: c_int,
    pub status: i32,
}

unsafe extern "C" {
    pub fn vault_probe(path: *const c_char) -> VaultProbe;
    pub fn vault_has_keychain(vault: *mut Vault) -> bool;
    pub fn vault_create(
        path: *const c_char,
        password: *const c_void,
        length: u32,
        out: *mut *mut Vault,
        metadata_unchanged: *mut bool,
    ) -> i32;
    pub fn vault_unchanged(vault: *mut Vault, equal: *mut bool) -> i32;
    pub fn vault_unlock(vault: *mut Vault, password: *const c_void, length: u32) -> i32;
    pub fn vault_is_unlocked(vault: *mut Vault, unlocked: *mut bool) -> i32;
    pub fn vault_add(vault: *mut Vault, bytes: *const c_void, length: u32) -> i32;
    pub fn vault_update(vault: *mut Vault, bytes: *const c_void, length: u32) -> i32;
    pub fn vault_read_equals(
        vault: *mut Vault,
        bytes: *const c_void,
        length: u32,
        equal: *mut bool,
        data_returned: *mut bool,
    ) -> i32;
    pub fn vault_delete(vault: *mut Vault) -> i32;
    pub fn vault_lock(vault: *mut Vault) -> i32;
    pub fn vault_read_status(
        vault: *mut Vault,
        data_returned: *mut bool,
        queried: *mut bool,
    ) -> i32;
    pub fn vault_release(vault: *mut Vault);
}
