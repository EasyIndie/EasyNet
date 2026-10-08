//! Only the actual owned labresult binary, bounded fixtures and three-second runs.
use std::{io::{Read, Write}, process::{Child, Command, ExitStatus, Stdio}, thread, time::{Duration, Instant}};
const CANONICAL: &str = r#"{"kind":"easynet-lab-result","schemaVersion":1,"operationId":"fixture_1","outcome":"unknown","ownerRetained":true,"outputBytes":4}"#;
struct OwnedChild(Option<Child>);
impl OwnedChild {
    fn stop(&mut self) {
        if let Some(child) = self.0.as_mut() {
            // Retain ownership until wait succeeds, including polling/error paths.
            let _ = child.kill();
            if child.wait().is_ok() { self.0 = None; }
        }
    }
}
impl Drop for OwnedChild { fn drop(&mut self) { self.stop(); } }
fn drain(mut reader: impl Read) -> (Vec<u8>, bool) {
    let mut data = Vec::new(); let mut overflow = false; let mut buf = [0; 1024];
    loop {
        let n = match reader.read(&mut buf) {
            Ok(0) => break, Ok(n) => n,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => panic!("owned pipe read failed"),
        };
        let retained = n.min(4096-data.len()); data.extend_from_slice(&buf[..retained]);
        overflow |= retained != n; // Continue draining; retention remains capped.
    }
    (data, overflow)
}
fn command(input: &[u8], args: &[&str]) -> (ExitStatus, Vec<u8>, Vec<u8>) {
    assert!(input.len() <= 4097);
    let started = Instant::now();
    let mut child = OwnedChild(Some(Command::new(env!("CARGO_BIN_EXE_labresult"))
        .args(args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap()));
    let process = child.0.as_mut().unwrap();
    let stdout = process.stdout.take().unwrap(); let stderr = process.stderr.take().unwrap();
    let out_thread = thread::spawn(move || drain(stdout)); let err_thread = thread::spawn(move || drain(stderr));
    // At most 4097 bytes, below the host pipe capacity; only this binary reads it.
    let write_result = process.stdin.take().unwrap().write_all(input);
    let status = loop {
        match child.0.as_mut().unwrap().try_wait() {
            Ok(Some(status)) => { child.0 = None; break Ok(status); }
            Ok(None) if started.elapsed() < Duration::from_secs(3) => thread::sleep(Duration::from_millis(5)),
            Ok(None) => { child.stop(); break Err("owned binary exceeded three seconds"); }
            Err(_) => { child.stop(); break Err("owned binary poll failed"); }
        }
    };
    let out = out_thread.join().unwrap(); let err = err_thread.join().unwrap();
    assert!(!out.1 && !err.1, "owned stream exceeded capture bound");
    if args.is_empty() { assert!(write_result.is_ok()); }
    (status.expect("owned binary failed"), out.0, err.0)
}
#[test]
fn actual_cli_contract() {
    let mut cases = vec![
        ("canonical", CANONICAL.as_bytes().to_vec(), true),
        ("normalize", format!(" \n{CANONICAL}\t ").into_bytes(), true),
        ("input boundary", format!("{CANONICAL}{}", " ".repeat(4096-CANONICAL.len())).into_bytes(), true),
        ("empty", vec![], false), ("malformed", br#"{"sensitive":"fixture-secret""#.to_vec(), false),
        ("duplicate", CANONICAL.replacen("\"kind\":", "\"kind\":\"easynet-lab-result\",\"kind\":", 1).into_bytes(), false),
        ("escaped duplicate", CANONICAL.replacen("\"kind\":", "\"k\\u0069nd\":\"easynet-lab-result\",\"kind\":", 1).into_bytes(), false),
        ("null", CANONICAL.replace("\"outputBytes\":4", "\"outputBytes\":null").into_bytes(), false),
        ("oversize", format!("{CANONICAL}{}", " ".repeat(4097-CANONICAL.len())).into_bytes(), false),
        ("second value", format!("{CANONICAL}{{}}").into_bytes(), false),
        ("invalid utf8", vec![0xff], false),
        ("unicode id", CANONICAL.replace("fixture_1", "秘密").into_bytes(), false),
        ("case alias", CANONICAL.replace("kind", "Kind").into_bytes(), false),
        ("missing", CANONICAL.replace(",\"outputBytes\":4", "").into_bytes(), false),
        ("unknown field", CANONICAL.replacen("{", "{\"sensitive\":\"fixture-secret\",", 1).into_bytes(), false),
    ];
    for (name, token) in [("fraction", "4.0"), ("exponent", "4e0"), ("negative zero", "-0"),
        ("overflow", "184467440737095516160"), ("byte limit", "4097"), ("numeric string", "\"4\""),
        ("compound", "[]")] {
        cases.push((name, CANONICAL.replace("\"outputBytes\":4", &format!("\"outputBytes\":{token}")).into_bytes(), false));
    }
    for (name, token) in [("schema fraction", "1.0"), ("schema exponent", "1e0"), ("schema version", "2")] {
        cases.push((name, CANONICAL.replace("\"schemaVersion\":1", &format!("\"schemaVersion\":{token}")).into_bytes(), false));
    }
    for (name, input, success) in &cases {
        let (status, out, err) = command(input, &[]);
        assert_eq!(status.code(), Some(if *success { 0 } else { 2 }), "{name}");
        assert_eq!(out, if *success { CANONICAL.as_bytes() } else { b"" }, "{name}");
        assert_eq!(err, if *success { &b""[..] } else { &b"invalid lab input\n"[..] }, "{name}");
    }
    let (status, out, err) = command(CANONICAL.as_bytes(), &["fixture-secret"]);
    assert_eq!(status.code(), Some(2)); assert!(out.is_empty()); assert_eq!(err, b"invalid lab arguments\n");
    // Additional accepted semantics have their own normalized records.
    for input in [CANONICAL.replace("\"outputBytes\":4", "\"outputBytes\":0"),
        CANONICAL.replace("\"outputBytes\":4", "\"outputBytes\":4096"),
        CANONICAL.replace("unknown", "fixture-complete-observed"),
        CANONICAL.replace("unknown", "not-dispatched").replace("true", "false").replace("\"outputBytes\":4", "\"outputBytes\":0")] {
        let (status, out, err) = command(input.as_bytes(), &[]);
        assert!(status.success()); assert_eq!(out, input.as_bytes()); assert!(err.is_empty());
    }
    assert_eq!(cases.len() + 1 + 4, 30);
}
#[test]
fn capture_bound_drains_without_retaining_excess() {
    let (out, overflow) = drain(&vec![0; 4097][..]); assert_eq!(out.len(), 4096); assert!(overflow);
    let (out, overflow) = drain(&vec![0; 4096][..]); assert_eq!(out.len(), 4096); assert!(!overflow);
}
