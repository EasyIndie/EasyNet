//! Stream ownership evidence is separate from future/task join evidence.
use std::{io, pin::Pin, task::{Context, Poll}};
use tokio::{io::{AsyncRead, AsyncWrite, ReadBuf}, sync::oneshot};

pub struct OwnedStream<S> {
    stream: Option<S>,
    dropped: Option<oneshot::Sender<()>>,
}
impl<S> OwnedStream<S> {
    pub(crate) fn new(stream: S, dropped: oneshot::Sender<()>) -> Self {
        Self { stream: Some(stream), dropped: Some(dropped) }
    }
}
impl<S> Drop for OwnedStream<S> {
    fn drop(&mut self) {
        // Publish evidence only after the wrapped resource has been released.
        drop(self.stream.take());
        if let Some(sender) = self.dropped.take() { let _ = sender.send(()); }
    }
}
impl<S: AsyncRead + Unpin> AsyncRead for OwnedStream<S> {
    fn poll_read(self: Pin<&mut Self>, cx: &mut Context<'_>, buf: &mut ReadBuf<'_>) -> Poll<io::Result<()>> {
        Pin::new(self.get_mut().stream.as_mut().expect("owned stream")).poll_read(cx, buf)
    }
}
impl<S: AsyncWrite + Unpin> AsyncWrite for OwnedStream<S> {
    fn poll_write(self: Pin<&mut Self>, cx: &mut Context<'_>, buf: &[u8]) -> Poll<io::Result<usize>> {
        Pin::new(self.get_mut().stream.as_mut().expect("owned stream")).poll_write(cx, buf)
    }
    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(self.get_mut().stream.as_mut().expect("owned stream")).poll_flush(cx)
    }
    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(self.get_mut().stream.as_mut().expect("owned stream")).poll_shutdown(cx)
    }
    fn is_write_vectored(&self) -> bool { self.stream.as_ref().expect("owned stream").is_write_vectored() }
    fn poll_write_vectored(self: Pin<&mut Self>, cx: &mut Context<'_>, bufs: &[io::IoSlice<'_>]) -> Poll<io::Result<usize>> {
        Pin::new(self.get_mut().stream.as_mut().expect("owned stream")).poll_write_vectored(cx, bufs)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    #[test]
    fn wrapped_drop_precedes_notifier_publication() {
        use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
        struct Resource { flag: Arc<AtomicBool>, receiver: Arc<Mutex<oneshot::Receiver<()>>> }
        impl Drop for Resource {
            fn drop(&mut self) {
                // This detects early publication deterministically, without a race.
                assert!(matches!(self.receiver.lock().expect("memory lock").try_recv(),
                    Err(oneshot::error::TryRecvError::Empty)));
                self.flag.store(true, Ordering::SeqCst);
            }
        }
        let (tx, rx) = oneshot::channel();
        let receiver = Arc::new(Mutex::new(rx));
        let flag = Arc::new(AtomicBool::new(false));
        drop(OwnedStream::new(Resource { flag: flag.clone(), receiver: receiver.clone() }, tx));
        assert_eq!(receiver.lock().expect("memory lock").try_recv(), Ok(()));
        assert!(flag.load(Ordering::SeqCst));
    }
    #[tokio::test]
    async fn memory_forwarding_and_drop_evidence() {
        let (stream, mut peer) = tokio::io::duplex(16);
        let (tx, mut rx) = oneshot::channel();
        let mut owned = OwnedStream::new(stream, tx);
        owned.write_all(b"fixture").await.expect("memory write");
        owned.flush().await.expect("memory flush");
        let mut buf = [0; 7];
        peer.read_exact(&mut buf).await.expect("memory read");
        assert_eq!(&buf, b"fixture");
        peer.write_all(b"ok").await.expect("memory peer write");
        owned.read_exact(&mut buf[..2]).await.expect("memory owned read");
        assert_eq!(&buf[..2], b"ok");
        owned.shutdown().await.expect("memory shutdown");
        assert!(matches!(rx.try_recv(), Err(oneshot::error::TryRecvError::Empty)));
        drop(owned);
        assert_eq!(rx.await, Ok(()));
        assert_eq!(peer.read(&mut buf).await.expect("memory EOF"), 0);
    }
}
