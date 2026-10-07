//! Build-only scoped vault adapter; native execution requires a separate gate.
mod ffi;
use std::{ffi::{CString, OsString}, io::{Read, Write}, ptr};
use ffi::{Vault, VaultProbe};
unsafe extern "C" { fn geteuid() -> u32; } // SDK uid_t is __uint32_t.

const CHECKS: [&str; 21] = [
    "password_generated", "create_guard", "creation_metadata_unchanged", "unlock_native",
    "unlocked_confirmed", "add", "read_initial_checked", "update", "read_updated_checked",
    "delete", "deleted_absent", "readd", "read_readded_checked", "lock_native",
    "locked_confirmed", "locked_read_queried", "locked_read_rejected", "final_metadata_unchanged",
    "create_wrapper_present", "create_keychain_ref_present", "locked_read_data_returned",
];
const STAGES: [&str; 15] = [
    "create_guard", "unlock_native", "unlock_state_native", "add", "read_initial_checked",
    "update", "read_updated_checked", "delete", "deleted_read_native", "readd",
    "read_readded_checked", "lock_native", "lock_state_native", "locked_read_native", "final_metadata",
];
#[derive(Clone, Copy, PartialEq, Eq)]
enum Outcome { Rejected, Blocked, Pass }
struct Report { outcome: Outcome, checks: [bool; 21], statuses: [Option<i32>; 15] }
impl Report {
    fn new() -> Self { Self { outcome: Outcome::Rejected, checks: [false; 21], statuses: [None; 15] } }
    fn status(&mut self, stage: usize, status: i32) -> bool {
        self.statuses[stage] = Some(status); status == 0
    }
    fn finish(&mut self) {
        if self.checks[..18].iter().all(|value| *value) { self.outcome = Outcome::Pass; }
    }
    fn json(&self) -> String {
        let outcome = match self.outcome { Outcome::Rejected => "rejected", Outcome::Blocked => "blocked", Outcome::Pass => "pass" };
        let statuses = self.statuses.iter().enumerate().filter_map(|(i, value)|
            value.map(|value| format!("\"{}\":{}", STAGES[i], value))).collect::<Vec<_>>().join(",");
        let checks = CHECKS.iter().zip(self.checks).map(|(key, value)|
            format!("\"{key}\":{value}")).collect::<Vec<_>>().join(",");
        format!("{{\"outcome\":\"{outcome}\",\"statuses\":{{{statuses}}},\"checks\":{{{checks}}}}}\n")
    }
}
struct Args { probe: bool, path: CString }
fn parse(args: &[OsString]) -> Option<Args> {
    let (probe, directory) = match args {
        [directory] if directory != "--probe" => (false, directory),
        [flag, directory] if flag == "--probe" => (true, directory),
        _ => return None,
    };
    let directory = directory.to_str()?;
    if directory.is_empty() || directory.len() > 4096 || directory.as_bytes().contains(&0) { return None; }
    // Append the fixed basename without resolving or normalizing the caller's path.
    Some(Args { probe, path: CString::new(format!("{directory}/fixture.keychain")).ok()? })
}
fn probe_json(result: VaultProbe) -> String {
    format!("{{\"path_guard_ok\":{},\"stage\":{},\"status\":{}}}\n", result.path_guard_ok, result.stage, result.status)
}
struct Secrets { raw: [u8; 32], password: [u8; 64], first: [u8; 11], second: [u8; 11] }
impl Secrets {
    fn new() -> Self { Self { raw: [0; 32], password: [0; 64], first: *b"fixture-one", second: *b"fixture-two" } }
    fn generate(&mut self) -> bool {
        if std::fs::File::open("/dev/urandom").and_then(|mut file| file.read_exact(&mut self.raw)).is_err() { return false; }
        const HEX: &[u8; 16] = b"0123456789abcdef";
        for (i, byte) in self.raw.iter().enumerate() {
            self.password[2 * i] = HEX[(byte >> 4) as usize]; self.password[2 * i + 1] = HEX[(byte & 15) as usize];
        }
        self.raw.fill(0); true
    }
}
impl Drop for Secrets {
    fn drop(&mut self) { self.raw.fill(0); self.password.fill(0); self.first.fill(0); self.second.fill(0); }
}
struct OwnedVault(*mut Vault);
impl Drop for OwnedVault {
    fn drop(&mut self) {
        // SAFETY: only the raw out-pointer returned by vault_create is wrapped,
        // once, including failure/null. C's null-safe release frees that wrapper.
        unsafe { ffi::vault_release(self.0); }
    }
}
fn read_checked(owner: &OwnedVault, bytes: &[u8; 11], report: &mut Report, stage: usize, check: usize) -> bool {
    let (mut equal, mut returned) = (false, false);
    // SAFETY: retained create owner, live 11-byte borrowed array and bool outputs;
    // C does not retain bytes/output pointers; 11 is representable by UInt32.
    let status = unsafe { ffi::vault_read_equals(owner.0, bytes.as_ptr().cast(), 11, &mut equal, &mut returned) };
    report.checks[check] = report.status(stage, status) && equal && returned;
    report.checks[check]
}
fn run(path: &CString) -> Report {
    let mut report = Report::new();
    // SAFETY: system getter has no arguments; SDK return uid_t is u32.
    if unsafe { geteuid() } == 0 { return report; }
    report.outcome = Outcome::Blocked;
    let mut secrets = Secrets::new();
    if !secrets.generate() { return report; }
    report.checks[0] = true;
    let (mut raw, mut unchanged) = (ptr::null_mut(), false);
    // SAFETY: path is live NUL-terminated CString; 64-byte password and outputs
    // are borrowed synchronously. C returns an owned wrapper even on some errors.
    let status = unsafe { ffi::vault_create(path.as_ptr(), secrets.password.as_ptr().cast(), 64, &mut raw, &mut unchanged) };
    let owner = OwnedVault(raw); // Immediately own every returned pointer, null included.
    report.checks[18] = !owner.0.is_null();
    // SAFETY: C accepts the retained wrapper or null, and does not transfer it.
    report.checks[19] = unsafe { ffi::vault_has_keychain(owner.0) };
    report.checks[2] = unchanged;
    report.checks[1] = report.status(0, status);
    // Every return below exits only this closure; final metadata always precedes Drop.
    let mut stages = || {
        if !report.checks[1] || !unchanged { return; }
        // SAFETY for this synchronous block: owner retains C wrapper; C guards its
        // ownedRef/readiness. Fixed arrays are live with lengths 64/11 <= UInt32;
        // bool outputs are initialized/live, borrowed only during each C call.
        unsafe {
            report.checks[3] = report.status(1, ffi::vault_unlock(owner.0, secrets.password.as_ptr().cast(), 64));
            if !report.checks[3] { return; }
            let mut unlocked = false;
            let status = ffi::vault_is_unlocked(owner.0, &mut unlocked);
            report.checks[4] = report.status(2, status) && unlocked;
            if !report.checks[4] { return; }
            report.checks[5] = report.status(3, ffi::vault_add(owner.0, secrets.first.as_ptr().cast(), 11));
            if !report.checks[5] || !read_checked(&owner, &secrets.first, &mut report, 4, 6) { return; }
            report.checks[7] = report.status(5, ffi::vault_update(owner.0, secrets.second.as_ptr().cast(), 11));
            if !report.checks[7] || !read_checked(&owner, &secrets.second, &mut report, 6, 8) { return; }
            report.checks[9] = report.status(7, ffi::vault_delete(owner.0));
            if !report.checks[9] { return; }
            let (mut returned, mut queried) = (false, false);
            let status = ffi::vault_read_status(owner.0, &mut returned, &mut queried);
            report.status(8, status);
            report.checks[10] = queried && status == -25300 && !returned; // errSecItemNotFound.
            if !report.checks[10] { return; }
            report.checks[11] = report.status(9, ffi::vault_add(owner.0, secrets.first.as_ptr().cast(), 11));
            if !report.checks[11] || !read_checked(&owner, &secrets.first, &mut report, 10, 12) { return; }
            report.checks[13] = report.status(11, ffi::vault_lock(owner.0));
            if !report.checks[13] { return; }
            let status = ffi::vault_is_unlocked(owner.0, &mut unlocked);
            report.checks[14] = report.status(12, status) && !unlocked;
            if !report.checks[14] { return; }
            let status = ffi::vault_read_status(owner.0, &mut returned, &mut queried);
            report.status(13, status);
            report.checks[15] = queried; report.checks[20] = returned;
            report.checks[16] = queried && status != 0 && !returned;
        }
    };
    stages();
    let mut final_equal = false;
    // SAFETY: same retained wrapper/null, live bool; C null case returns -50.
    let status = unsafe { ffi::vault_unchanged(owner.0, &mut final_equal) };
    report.checks[17] = report.status(14, status) && final_equal;
    report.finish();
    drop(owner); // Exactly one release before the report can be printed.
    report
}
fn main() {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let probe_mode = args.first().is_some_and(|arg| arg == "--probe");
    let parsed = parse(&args);
    let (output, code) = if probe_mode {
        let mut result = VaultProbe { path_guard_ok: false, stage: 0, status: -50 };
        if let Some(args) = parsed {
            // SAFETY: SDK getter, then synchronous C probe with live CString;
            // private_path guards before read-only metadata; root never enters C.
            if args.probe && unsafe { geteuid() } != 0 { result = unsafe { ffi::vault_probe(args.path.as_ptr()) }; }
        }
        (probe_json(result), 0)
    } else {
        let report = parsed.map_or_else(Report::new, |args| run(&args.path));
        let code = if report.outcome == Outcome::Pass { 0 } else { 1 };
        (report.json(), code)
    };
    // run returned only after releasing its owner and dropping secret buffers.
    if std::io::stdout().lock().write_all(output.as_bytes()).is_err() { std::process::exit(1); }
    std::process::exit(code);
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::ffi::OsStringExt;
    #[test]
    fn parser_keeps_path_literal_and_accepts_only_two_forms() {
        let args = parse(&[OsString::from("/tmp/example/../literal")]).unwrap();
        assert!(!args.probe); assert_eq!(args.path.to_bytes(), b"/tmp/example/../literal/fixture.keychain");
        assert!(parse(&["--probe".into(), "/tmp/example".into()]).unwrap().probe);
        assert!(parse(&["a".repeat(4096).into()]).is_some());
    }
    #[test]
    fn parser_rejects_malformed_and_extra_arguments() {
        for args in [vec![], vec!["".into()], vec!["--probe".into()], vec!["a\0b".into()],
            vec!["a".repeat(4097).into()], vec![OsString::from_vec(vec![0xff])],
            vec!["one".into(), "two".into()], vec!["--probe".into(), "one".into(), "two".into()]] {
            assert!(parse(&args).is_none());
        }
    }
    #[test]
    fn rejected_report_has_fixed_schema_and_no_native_claim() {
        let report = Report::new(); let json = report.json();
        assert!(json.starts_with("{\"outcome\":\"rejected\",\"statuses\":{},\"checks\":{"));
        assert_eq!(json.matches(":false").count(), 21); assert!(json.len() < 4096);
        assert!(!json.contains("password\":") && !json.contains("fixture-one"));
        assert_eq!(probe_json(VaultProbe { path_guard_ok: false, stage: 0, status: -50 }),
            "{\"path_guard_ok\":false,\"stage\":0,\"status\":-50}\n");
    }
    #[test]
    fn blocked_report_preserves_allowlisted_numeric_failures() {
        let mut report = Report::new(); report.outcome = Outcome::Blocked;
        report.status(8, -25300); report.status(14, -50); report.finish();
        assert!(report.outcome == Outcome::Blocked);
        let json = report.json(); assert!(json.contains("\"deleted_read_native\":-25300"));
        assert!(json.contains("\"final_metadata\":-50")); assert!(json.len() < 4096);
    }
}
