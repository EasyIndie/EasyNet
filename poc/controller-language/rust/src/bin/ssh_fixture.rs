//! KEX-only bridge stage: no authentication, channel or command is started.
use easynet_ssh_lab::{control::{Control, ControlToken}, decode_frame, Credentials,
    transport::{Transport, TransportError}};
use std::io::{Read, Write};
use std::os::fd::{FromRawFd, RawFd};
use std::os::unix::net::UnixStream;
use std::time::Duration;

const IO_FAILURE: &str = "fixture I/O failure";
const INVALID_INPUT: &str = "invalid fixture input";
const SSH_FAILURE: &str = "fixture SSH failure";
const CLEANUP_FAILURE: &str = "fixture cleanup failure";

fn validate_socket(fd: RawFd) -> Result<(), &'static str> {
    let mut kind: libc::c_int = 0;
    let mut kind_len = std::mem::size_of_val(&kind) as libc::socklen_t;
    // SAFETY: kind and kind_len are live writable buffers of their specified
    // sizes. This borrowed descriptor is inspected, never closed or transferred.
    let result = unsafe { libc::getsockopt(fd, libc::SOL_SOCKET, libc::SO_TYPE,
        (&mut kind as *mut libc::c_int).cast(), &mut kind_len) };
    if result != 0 || kind_len as usize != std::mem::size_of_val(&kind)
        || kind != libc::SOCK_STREAM {
        return Err(IO_FAILURE);
    }
    // SAFETY: zero is a valid initial byte representation for sockaddr_storage.
    let mut address: libc::sockaddr_storage = unsafe { std::mem::zeroed() };
    let mut address_len = std::mem::size_of_val(&address) as libc::socklen_t;
    // SAFETY: storage is aligned and sized for the address, and address_len
    // points to its live capacity. getpeername only inspects the borrowed fd.
    let result = unsafe { libc::getpeername(fd,
        (&mut address as *mut libc::sockaddr_storage).cast(), &mut address_len) };
    let min_len = std::mem::offset_of!(libc::sockaddr_storage, ss_family)
        + std::mem::size_of_val(&address.ss_family);
    if result != 0 || (address_len as usize) < min_len
        || address_len as usize > std::mem::size_of_val(&address)
        || i32::from(address.ss_family) != libc::AF_UNIX {
        return Err(IO_FAILURE);
    }
    Ok(())
}

fn inherited_control() -> Result<UnixStream, &'static str> {
    validate_socket(3)?;
    // SAFETY: the dedicated single-threaded child owns inherited fd 3, which
    // was validated as a connected Unix stream. No other owner/conversion is
    // created; the returned stream alone closes it on every subsequent path.
    Ok(unsafe { UnixStream::from_raw_fd(3) })
}

fn event(line: &[u8]) -> Result<(), &'static str> {
    let mut output = std::io::stdout().lock();
    output.write_all(line).and_then(|_| output.flush()).map_err(|_| IO_FAILURE)
}

async fn bootstrap(stream: UnixStream, credentials: Credentials) -> Result<(), &'static str> {
    let deadline = tokio::time::Instant::now()
        + Duration::from_millis(u64::from(credentials.deadline_ms));
    let mut control = Control::new(stream).map_err(|_| IO_FAILURE)?;
    event(b"ready\n")?;
    let token = tokio::time::timeout_at(deadline, control.next()).await
        .map_err(|_| IO_FAILURE)?.map_err(|_| IO_FAILURE)?;
    if token == ControlToken::Cancel {
        drop(control);
        event(b"not-dispatched\n")?;
        return event(b"joined\n");
    }

    let mut owner = Transport::new(credentials.port, credentials.host_key)
        .map_err(|_| SSH_FAILURE)?;
    let mut cancellation = None;
    let outcome = {
        // The future borrows control and its recorded outcome. End both borrows
        // before inspecting cancellation or dropping the owned IPC stream.
        let mut cancel = Box::pin(async {
            cancellation = Some(match control.next().await {
                Ok(ControlToken::Cancel) => Ok(()),
                Ok(ControlToken::Go) | Err(_) => Err(IO_FAILURE),
            });
        });
        let result = owner.connect_until(deadline, cancel.as_mut()).await;
        drop(cancel);
        result
    };
    // Every path after owner creation must prove cleanup. A failed retained
    // owner stays alive until process containment; it must never unwind/drop.
    let proof = match owner.close_join().await {
        Ok(proof) => proof,
        Err(_) => {
            let _ = writeln!(std::io::stderr().lock(), "{CLEANUP_FAILURE}");
            std::process::exit(2);
        }
    };
    drop(control);
    let result = match cancellation {
        Some(Err(_)) => Err(IO_FAILURE),
        _ => match outcome {
            Ok(()) => Ok(()),
            Err(TransportError::Cancelled) if cancellation == Some(Ok(())) => Ok(()),
            Err(_) => Err(SSH_FAILURE),
        },
    };
    // This stage's success/cancel exit 0 is only a KEX experiment exception.
    // Neither event asserts auth, exec or a completed fixture operation.
    let _joined = proof;
    event(b"not-dispatched\n")?;
    event(b"joined\n")?;
    result
}

fn run() -> Result<(), &'static str> {
    if std::env::args_os().skip(1).next().is_some() { return Err(INVALID_INPUT); }
    let mut frame = Vec::new();
    std::io::stdin().lock().take(8193).read_to_end(&mut frame).map_err(|_| IO_FAILURE)?;
    let credentials = decode_frame(&frame).map_err(|_| INVALID_INPUT)?;
    let stream = inherited_control()?;
    let runtime = tokio::runtime::Builder::new_current_thread().enable_all()
        .build().map_err(|_| IO_FAILURE)?;
    runtime.block_on(bootstrap(stream, credentials))
}

fn main() {
    if let Err(message) = run() {
        let _ = writeln!(std::io::stderr().lock(), "{message}");
        std::process::exit(2);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::fd::AsRawFd;
    use std::os::unix::net::UnixDatagram;

    #[test]
    fn borrowed_connected_unix_pair_validates_without_taking_ownership() {
        let (mut stream, mut peer) = UnixStream::pair().expect("fixture pair");
        assert_eq!(validate_socket(stream.as_raw_fd()), Ok(()));
        assert_eq!(validate_socket(peer.as_raw_fd()), Ok(()));
        stream.write_all(b"G").expect("fixture write");
        let mut byte = [0]; peer.read_exact(&mut byte).expect("fixture read");
        assert_eq!(byte, *b"G");
    }
    #[test]
    fn datagram_and_invalid_descriptor_return_only_fixed_error() {
        let (socket, _peer) = UnixDatagram::pair().expect("fixture pair");
        assert_eq!(validate_socket(socket.as_raw_fd()), Err(IO_FAILURE));
        assert_eq!(validate_socket(-1), Err(IO_FAILURE));
    }
}
