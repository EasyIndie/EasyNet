mod ffi;
use std::ffi::{c_char, c_void};
use std::hint::black_box;
use std::mem::{align_of, offset_of, size_of};

unsafe extern "C" {
    fn abi_value(index: u32) -> u64;
    fn abi_echo_bool(value: bool) -> bool;
    fn abi_flip_bool(value: *mut bool);
    fn abi_return_probe() -> ffi::VaultProbe;
    fn abi_echo_status(value: i32) -> i32;
    fn abi_echo_u32(value: u32) -> u32;
}

fn main() {
    let expected = [
        size_of::<bool>(), align_of::<bool>(), size_of::<i32>(), align_of::<i32>(),
        usize::from(i32::MIN < 0), size_of::<u32>(), align_of::<u32>(),
        usize::from(u32::MAX > 0), size_of::<ffi::VaultProbe>(),
        align_of::<ffi::VaultProbe>(), offset_of!(ffi::VaultProbe, path_guard_ok),
        offset_of!(ffi::VaultProbe, stage), offset_of!(ffi::VaultProbe, status),
    ];
    for (index, rust_value) in expected.into_iter().enumerate() {
        let c_value = unsafe { abi_value(index as u32) };
        assert_eq!(c_value, rust_value as u64, "ABI index {index}");
    }
    // The C shim returns only valid C bool values and a VaultProbe initialized
    // with true/42/-50. `flipped` is live, aligned, uniquely borrowed storage;
    // abi_flip_bool borrows it only for this synchronous call and retains no pointer.
    for value in [false, true] {
        assert_eq!(unsafe { abi_echo_bool(value) }, value);
        let mut flipped = value;
        unsafe { abi_flip_bool(&mut flipped) };
        assert_eq!(flipped, !value);
    }
    let probe = unsafe { abi_return_probe() };
    assert!(probe.path_guard_ok);
    assert_eq!(probe.stage, 42);
    assert_eq!(probe.status, -50);
    assert_eq!(unsafe { abi_echo_status(0) }, 0);
    assert_eq!(unsafe { abi_echo_status(-50) }, -50);
    assert_eq!(unsafe { abi_echo_u32(0) }, 0);
    assert_eq!(unsafe { abi_echo_u32(u32::MAX) }, u32::MAX);

    // Resolve all 13 helper symbols without invoking any helper function.
    macro_rules! keep_symbol {
        ($symbol:path, $signature:ty) => {{
            let address = black_box($symbol as $signature as *const () as usize);
            assert_ne!(address, 0);
        }};
    }
    keep_symbol!(ffi::vault_probe, unsafe extern "C" fn(*const c_char) -> ffi::VaultProbe);
    keep_symbol!(ffi::vault_has_keychain, unsafe extern "C" fn(*mut ffi::Vault) -> bool);
    keep_symbol!(ffi::vault_create, unsafe extern "C" fn(*const c_char, *const c_void, u32, *mut *mut ffi::Vault, *mut bool) -> i32);
    keep_symbol!(ffi::vault_unchanged, unsafe extern "C" fn(*mut ffi::Vault, *mut bool) -> i32);
    keep_symbol!(ffi::vault_unlock, unsafe extern "C" fn(*mut ffi::Vault, *const c_void, u32) -> i32);
    keep_symbol!(ffi::vault_is_unlocked, unsafe extern "C" fn(*mut ffi::Vault, *mut bool) -> i32);
    keep_symbol!(ffi::vault_add, unsafe extern "C" fn(*mut ffi::Vault, *const c_void, u32) -> i32);
    keep_symbol!(ffi::vault_update, unsafe extern "C" fn(*mut ffi::Vault, *const c_void, u32) -> i32);
    keep_symbol!(ffi::vault_read_equals, unsafe extern "C" fn(*mut ffi::Vault, *const c_void, u32, *mut bool, *mut bool) -> i32);
    keep_symbol!(ffi::vault_delete, unsafe extern "C" fn(*mut ffi::Vault) -> i32);
    keep_symbol!(ffi::vault_lock, unsafe extern "C" fn(*mut ffi::Vault) -> i32);
    keep_symbol!(ffi::vault_read_status, unsafe extern "C" fn(*mut ffi::Vault, *mut bool, *mut bool) -> i32);
    keep_symbol!(ffi::vault_release, unsafe extern "C" fn(*mut ffi::Vault));
    println!("ABI/link data-only checks passed");
}
