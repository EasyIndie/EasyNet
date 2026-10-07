use easynet_ssh_lab::control::{Control, ControlError, ControlToken};
use std::os::unix::net::UnixStream;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

fn pair() -> (Control, tokio::net::UnixStream) {
    let (owned, peer) = UnixStream::pair().expect("fixture pair");
    peer.set_nonblocking(true).expect("fixture nonblocking");
    (Control::new(owned).expect("fixture control"),
        tokio::net::UnixStream::from_std(peer).expect("fixture peer"))
}
async fn next(c: &mut Control) -> Result<ControlToken, ControlError> {
    tokio::time::timeout(Duration::from_secs(1), c.next()).await.expect("bounded read")
}

#[tokio::test]
async fn go_then_cancel_and_terminal_never_reads_again() {
    let (mut c, mut peer) = pair();
    peer.write_all(b"GC").await.expect("fixture write");
    assert_eq!(next(&mut c).await, Ok(ControlToken::Go));
    assert_eq!(next(&mut c).await, Ok(ControlToken::Cancel));
    // Keep peer open without more bytes: an erroneous terminal read would hang.
    assert_eq!(next(&mut c).await, Err(ControlError::InvalidToken));
}

#[tokio::test]
async fn cancel_first_and_eof_in_both_phases() {
    let (mut c, mut peer) = pair();
    peer.write_all(b"C").await.expect("fixture write");
    assert_eq!(next(&mut c).await, Ok(ControlToken::Cancel));
    assert_eq!(next(&mut c).await, Err(ControlError::InvalidToken));
    for after_go in [false, true] {
        let (mut c, mut peer) = pair();
        if after_go {
            peer.write_all(b"G").await.expect("fixture write");
            assert_eq!(next(&mut c).await, Ok(ControlToken::Go));
        }
        drop(peer);
        assert_eq!(next(&mut c).await, Ok(ControlToken::Cancel));
        assert_eq!(next(&mut c).await, Err(ControlError::InvalidToken));
    }
}

#[tokio::test]
async fn duplicate_and_unknown_tokens_refuse_and_stay_terminal() {
    for bytes in [b"GG".as_slice(), b"GX", b"X"] {
        let (mut c, mut peer) = pair();
        peer.write_all(bytes).await.expect("fixture write");
        if bytes[0] == b'G' { assert_eq!(next(&mut c).await, Ok(ControlToken::Go)); }
        assert_eq!(next(&mut c).await, Err(ControlError::InvalidToken));
        assert_eq!(next(&mut c).await, Err(ControlError::InvalidToken));
    }
}

#[tokio::test]
async fn drop_closes_owned_stream_with_observed_peer_eof() {
    let (c, mut peer) = pair();
    drop(c);
    let mut byte = [0];
    assert_eq!(tokio::time::timeout(Duration::from_secs(1), peer.read(&mut byte))
        .await.expect("bounded peer EOF").expect("fixture peer read"), 0);
}

#[test]
fn outside_runtime_returns_fixed_io_error() {
    let (owned, _peer) = UnixStream::pair().expect("fixture pair");
    match Control::new(owned) {
        Err(e) => {
            assert_eq!(e, ControlError::IoFailure);
            assert_eq!(e.to_string(), "fixture I/O failure");
            assert_eq!(format!("{e:?}"), "IoFailure");
        }
        Ok(_) => panic!("outside runtime accepted"),
    }
}
