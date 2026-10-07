//! Retained connection ownership; callers must retain a failed-cleanup owner.
use crate::owned_stream::OwnedStream;
use russh::{client::{self, Handler, Handle}, keys::{Algorithm, PublicKey, PublicKeyOrCertificate}};
use std::{future::Future, net::{Ipv4Addr, Shutdown, SocketAddrV4}, pin::Pin, sync::Arc, time::Duration};
use tokio::{net::TcpStream, sync::oneshot, time::{Instant, timeout_at}};

#[derive(Debug, PartialEq, Eq)]
pub enum TransportError { Untrusted, Cancelled, Deadline, Io, Ssh, CleanupFailure, InvalidState }
impl From<russh::Error> for TransportError {
    fn from(_: russh::Error) -> Self { Self::Ssh }
}
impl std::fmt::Display for TransportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Untrusted => "untrusted fixture host", Self::Cancelled => "fixture cancelled",
            Self::Deadline => "fixture deadline", Self::Io => "fixture I/O failure",
            Self::Ssh => "fixture SSH failure", Self::CleanupFailure => "fixture cleanup failure",
            Self::InvalidState => "invalid fixture state",
        })
    }
}
impl std::error::Error for TransportError {}

pub struct ExpectedHost { wire: Vec<u8> }
impl Handler for ExpectedHost {
    type Error = TransportError;
    async fn check_server_key(&mut self, offered: &PublicKeyOrCertificate) -> Result<bool, Self::Error> {
        match offered {
            PublicKeyOrCertificate::PublicKey { key, .. } if key.algorithm() == Algorithm::Ed25519 => {
                Ok(key.to_bytes().map_err(|_| TransportError::Ssh)? == self.wire)
            }
            _ => Ok(false),
        }
    }
}
type Connect = Pin<Box<dyn Future<Output = Result<Handle<ExpectedHost>, TransportError>> + Send>>;
pub struct JoinedProof { _private: () }
pub struct Transport {
    port: u16,
    expected: Vec<u8>,
    attempted: bool,
    closing: bool,
    cleanup_deadline: Option<Instant>,
    cleanup_failed: bool,
    joined: bool,
    shutdown: Option<std::net::TcpStream>,
    pending: Option<Connect>,
    handle: Option<Handle<ExpectedHost>>,
    dropped: Option<oneshot::Receiver<()>>,
}
impl Transport {
    pub fn new(port: u16, expected: Option<PublicKey>) -> Result<Self, TransportError> {
        let key = expected.ok_or(TransportError::Untrusted)?;
        if key.algorithm() != Algorithm::Ed25519 { return Err(TransportError::Untrusted); }
        if port == 0 { return Err(TransportError::Io); }
        Ok(Self { port, expected: key.to_bytes().map_err(|_| TransportError::Untrusted)?,
            attempted: false, closing: false, cleanup_deadline: None,
            cleanup_failed: false, joined: false, shutdown: None,
            pending: None, handle: None, dropped: None })
    }
    pub fn handle_mut(&mut self) -> Option<&mut Handle<ExpectedHost>> {
        if self.closing || self.cleanup_failed || self.joined { None } else { self.handle.as_mut() }
    }
    pub async fn connect_until(&mut self, deadline: Instant, mut cancel: Pin<&mut impl Future<Output = ()>>) -> Result<(), TransportError> {
        if self.cleanup_failed { return Err(TransportError::CleanupFailure); }
        if self.attempted || self.closing || self.joined { return Err(TransportError::InvalidState); }
        self.attempted = true;
        let stream = tokio::select! {
            biased;
            _ = &mut cancel => return Err(TransportError::Cancelled),
            _ = tokio::time::sleep_until(deadline) => return Err(TransportError::Deadline),
            result = TcpStream::connect(SocketAddrV4::new(Ipv4Addr::LOCALHOST, self.port)) => result.map_err(|_| TransportError::Io)?,
        };
        let original = stream.into_std().map_err(|_| TransportError::Io)?;
        self.shutdown = Some(original.try_clone().map_err(|_| TransportError::Io)?);
        let stream = match TcpStream::from_std(original) {
            Ok(stream) => stream,
            Err(_) => { drop(self.shutdown.take()); return Err(TransportError::Io); }
        };
        let (tx, rx) = oneshot::channel();
        self.dropped = Some(rx);
        self.pending = Some(Box::pin(client::connect_stream(Arc::new(client::Config::default()),
            OwnedStream::new(stream, tx), ExpectedHost { wire: self.expected.clone() })));
        let outcome = tokio::select! {
            biased;
            _ = &mut cancel => Err(TransportError::Cancelled),
            _ = tokio::time::sleep_until(deadline) => Err(TransportError::Deadline),
            result = self.pending.as_mut().expect("owned connect future").as_mut() => {
                self.pending = None; // Resolved futures are never polled again.
                match result { Ok(handle) => { self.handle = Some(handle); Ok(()) }, Err(e) => Err(e) }
            }
        };
        match outcome {
            Ok(()) => Ok(()),
            Err(error) => { self.close_join().await?; Err(error) }
        }
    }
    pub async fn close_join(&mut self) -> Result<JoinedProof, TransportError> {
        // Persist at the first poll, including across cancellation of this borrow.
        self.closing = true;
        if self.cleanup_failed { return Err(TransportError::CleanupFailure); }
        if self.joined { return Ok(JoinedProof { _private: () }); }
        let deadline = *self.cleanup_deadline.get_or_insert_with(|| Instant::now() + Duration::from_millis(1000));
        if let Some(stream) = &self.shutdown { let _ = stream.shutdown(Shutdown::Both); }
        let result = self.join_retained(deadline).await;
        if result.is_err() { self.cleanup_failed = true; return Err(TransportError::CleanupFailure); }
        self.shutdown = None;
        self.joined = true;
        Ok(JoinedProof { _private: () })
    }
    async fn join_retained(&mut self, deadline: Instant) -> Result<(), ()> {
        if let Some(future) = self.pending.as_mut() {
            let result = timeout_at(deadline, future.as_mut()).await.map_err(|_| ())?;
            self.pending = None;
            if let Ok(handle) = result { self.handle = Some(handle); }
        }
        if let Some(handle) = self.handle.as_mut() {
            let _resolved = timeout_at(deadline, Pin::new(handle)).await.map_err(|_| ())?;
            self.handle = None; // Joined even if its session returned a fixed error.
        }
        if let Some(dropped) = self.dropped.as_mut() {
            timeout_at(deadline, dropped).await.map_err(|_| ())?.map_err(|_| ())?;
            self.dropped = None;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use russh::keys::{PrivateKey, EcdsaCurve, ssh_key::certificate::Builder};
    fn key() -> PrivateKey {
        PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).expect("memory fixture key")
    }
    #[test]
    fn unknown_trust_refuses_without_runtime() {
        assert!(matches!(Transport::new(1, None), Err(TransportError::Untrusted)));
    }
    #[tokio::test]
    async fn pure_trust_constructor_and_certificate_refusal() {
        assert!(matches!(Transport::new(1, None), Err(TransportError::Untrusted)));
        let private = key(); let public = private.public_key().clone();
        assert!(matches!(Transport::new(0, Some(public.clone())), Err(TransportError::Io)));
        let other = PrivateKey::random(&mut rand::rng(), Algorithm::Ecdsa { curve: EcdsaCurve::NistP256 })
            .expect("memory alternate key");
        assert!(matches!(Transport::new(1, Some(other.public_key().clone())), Err(TransportError::Untrusted)));
        let mut expected = ExpectedHost { wire: public.to_bytes().expect("public encoding") };
        assert!(expected.check_server_key(&public.clone().into()).await.expect("trust check"));
        assert!(!expected.check_server_key(&key().public_key().clone().into()).await.expect("trust check"));
        let mut builder = Builder::new(vec![1; 16], public.key_data().clone(), 0, 1).expect("certificate builder");
        builder.all_principals_valid().expect("certificate principals");
        let cert = builder.sign(&private).expect("memory certificate");
        assert!(!expected.check_server_key(&cert.into()).await.expect("certificate refusal"));
        assert_eq!(TransportError::from(russh::Error::Disconnect), TransportError::Ssh);
        assert_eq!(TransportError::CleanupFailure.to_string(), "fixture cleanup failure");
    }
    struct Pending(std::sync::Arc<std::sync::atomic::AtomicBool>);
    impl Future for Pending {
        type Output = Result<Handle<ExpectedHost>, TransportError>;
        fn poll(self: Pin<&mut Self>, _: &mut std::task::Context<'_>) -> std::task::Poll<Self::Output> {
            std::task::Poll::Pending
        }
    }
    impl Drop for Pending {
        fn drop(&mut self) { self.0.store(true, std::sync::atomic::Ordering::SeqCst); }
    }
    #[tokio::test]
    async fn cancelled_cleanup_borrow_retains_one_window_and_owner() {
        let flag = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let mut owner = Transport::new(1, Some(key().public_key().clone())).expect("trust constructor");
        owner.attempted = true;
        owner.pending = Some(Box::pin(Pending(flag.clone())));
        let mut first = Box::pin(owner.close_join());
        std::future::poll_fn(|cx| {
            assert!(first.as_mut().poll(cx).is_pending());
            std::task::Poll::Ready(())
        }).await;
        drop(first);
        let original_deadline = owner.cleanup_deadline.expect("cleanup window started");
        assert!(owner.closing);
        assert!(owner.handle_mut().is_none());
        assert!(!flag.load(std::sync::atomic::Ordering::SeqCst));
        let mut second = Box::pin(owner.close_join());
        std::future::poll_fn(|cx| {
            assert!(second.as_mut().poll(cx).is_pending());
            std::task::Poll::Ready(())
        }).await;
        drop(second);
        assert_eq!(owner.cleanup_deadline, Some(original_deadline));
        let result = timeout_at(original_deadline + Duration::from_millis(100), owner.close_join())
            .await.expect("original cleanup window bounded");
        assert!(matches!(result, Err(TransportError::CleanupFailure)));
        assert!(owner.pending.is_some());
        assert!(!flag.load(std::sync::atomic::Ordering::SeqCst));
        assert!(matches!(owner.close_join().await, Err(TransportError::CleanupFailure)));
        // Fake future only: explicit teardown after retained-owner assertions.
        drop(owner);
        assert!(flag.load(std::sync::atomic::Ordering::SeqCst));
    }
    #[tokio::test]
    async fn pending_cleanup_timeout_retains_owner_and_sticky_failure() {
        let flag = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let mut owner = Transport::new(1, Some(key().public_key().clone())).expect("trust constructor");
        owner.attempted = true;
        owner.pending = Some(Box::pin(Pending(flag.clone())));
        assert!(matches!(owner.close_join().await, Err(TransportError::CleanupFailure)));
        assert!(owner.pending.is_some());
        assert!(!flag.load(std::sync::atomic::Ordering::SeqCst));
        assert!(matches!(owner.close_join().await, Err(TransportError::CleanupFailure)));
        assert!(owner.handle_mut().is_none());
        let mut cancel = std::pin::pin!(std::future::pending());
        assert_eq!(owner.connect_until(Instant::now(), cancel.as_mut()).await, Err(TransportError::CleanupFailure));
        // Explicit test teardown only, after retention assertions; no real task exists.
        drop(owner);
        assert!(flag.load(std::sync::atomic::Ordering::SeqCst));
    }
    #[tokio::test]
    async fn completed_future_missing_drop_refuses_proof_without_repoll() {
        let mut owner = Transport::new(1, Some(key().public_key().clone())).expect("trust constructor");
        owner.attempted = true;
        owner.pending = Some(Box::pin(async { Err(TransportError::Ssh) }));
        let (tx, rx) = oneshot::channel(); drop(tx);
        owner.dropped = Some(rx);
        assert!(matches!(owner.close_join().await, Err(TransportError::CleanupFailure)));
        assert!(owner.pending.is_none());
        assert!(matches!(owner.close_join().await, Err(TransportError::CleanupFailure)));
    }
    #[tokio::test]
    async fn completed_error_and_observed_drop_allow_idempotent_join() {
        let mut owner = Transport::new(1, Some(key().public_key().clone())).expect("trust constructor");
        owner.attempted = true;
        owner.pending = Some(Box::pin(async { Err(TransportError::Ssh) }));
        let (tx, rx) = oneshot::channel(); tx.send(()).expect("fake drop evidence");
        owner.dropped = Some(rx);
        assert!(owner.close_join().await.is_ok());
        assert!(owner.close_join().await.is_ok());
        let mut cancel = std::pin::pin!(std::future::pending());
        assert_eq!(owner.connect_until(Instant::now(), cancel.as_mut()).await, Err(TransportError::InvalidState));
    }
}
