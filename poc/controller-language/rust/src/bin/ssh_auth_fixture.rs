//! Signed-auth-only bridge stage: no channel or command is started.
use easynet_ssh_lab::{control::{Control, ControlToken}, decode_frame, Credentials,
    transport::{Transport, TransportError}};
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::{sync::Arc, time::Duration};
use russh::keys::PrivateKeyWithHashAlg;

mod common;
use common::{event, inherited_control, IO_FAILURE, INVALID_INPUT, SSH_FAILURE, CLEANUP_FAILURE};

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
    let mut authenticated = false;
    let outcome = {
        // Keep this same borrowed future across KEX and auth. A completed
        // cancellation always ends KEX with an error, so it is never repolled.
        let mut cancel = Box::pin(async {
            cancellation = Some(match control.next().await {
                Ok(ControlToken::Cancel) => Ok(()),
                Ok(ControlToken::Go) | Err(_) => Err(IO_FAILURE),
            });
        });
        let result = match owner.connect_until(deadline, cancel.as_mut()).await {
            Err(error) => Err(error),
            Ok(()) => match owner.handle_mut() {
                None => Err(TransportError::InvalidState),
                Some(handle) => {
                    // The handle stays owned by Transport. Dropping this borrow
                    // on interruption leaves that owner responsible for joining.
                    let mut auth = Box::pin(handle.authenticate_publickey("fixture",
                        PrivateKeyWithHashAlg::new(Arc::new(credentials.private_key), None)));
                    tokio::select! {
                        biased;
                        _ = cancel.as_mut() => Err(TransportError::Cancelled),
                        _ = tokio::time::sleep_until(deadline) => Err(TransportError::Deadline),
                        result = auth.as_mut() => match result {
                            Ok(result) if result.success() => {
                                authenticated = true;
                                Ok(())
                            }
                            _ => Err(TransportError::Ssh),
                        }
                    }
                }
            },
        };
        // Auth and handle borrows ended above; end cancellation's borrows
        // before inspecting recorded state or closing the retained owner.
        drop(cancel);
        result
    };
    // Event errors are recorded, never propagated while the owner needs joining.
    let auth_event = if authenticated { event(b"authenticated\n") } else { Ok(()) };
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
    let result = match (auth_event, cancellation) {
        (Err(_), _) => Err(IO_FAILURE),
        (_, Some(Err(_))) => Err(IO_FAILURE),
        _ => match outcome {
            Ok(()) => Ok(()),
            Err(TransportError::Cancelled) if cancellation == Some(Ok(())) => Ok(()),
            Err(_) => Err(SSH_FAILURE),
        },
    };
    // This stage's auth-success/cancel exit 0 is an experiment exception.
    // It does not assert exec or a completed fixture operation.
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
