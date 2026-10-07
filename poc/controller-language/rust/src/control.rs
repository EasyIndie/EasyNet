//! Owned Unix control stream; each read future remains borrowed by its caller.
use std::os::unix::net::UnixStream;
use tokio::io::AsyncReadExt;

#[derive(Debug, PartialEq, Eq)]
pub enum ControlToken {
    Go,
    Cancel,
}
#[derive(Debug, PartialEq, Eq)]
pub enum ControlError {
    InvalidToken,
    IoFailure,
}
impl std::fmt::Display for ControlError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("fixture I/O failure")
    }
}
impl std::error::Error for ControlError {}

pub struct Control {
    stream: tokio::net::UnixStream,
    seen_go: bool,
    terminal: bool,
}
impl Control {
    /// Register this owned stream in an entered, I/O-enabled Tokio runtime.
    ///
    /// # Panics
    /// Tokio may panic if the entered runtime has I/O disabled. Runtime presence
    /// is checked here; the bridge must build its runtime with I/O enabled.
    pub fn new(stream: UnixStream) -> Result<Self, ControlError> {
        tokio::runtime::Handle::try_current().map_err(|_| ControlError::IoFailure)?;
        stream.set_nonblocking(true).map_err(|_| ControlError::IoFailure)?;
        let stream = tokio::net::UnixStream::from_std(stream)
            .map_err(|_| ControlError::IoFailure)?;
        Ok(Self { stream, seen_go: false, terminal: false })
    }

    pub async fn next(&mut self) -> Result<ControlToken, ControlError> {
        if self.terminal {
            return Err(ControlError::InvalidToken);
        }
        let mut byte = [0];
        match self.stream.read(&mut byte).await {
            Ok(0) => { self.terminal = true; Ok(ControlToken::Cancel) }
            Ok(_) if byte[0] == b'C' => { self.terminal = true; Ok(ControlToken::Cancel) }
            Ok(_) if byte[0] == b'G' && !self.seen_go => {
                self.seen_go = true;
                Ok(ControlToken::Go)
            }
            Ok(_) => { self.terminal = true; Err(ControlError::InvalidToken) }
            Err(_) => { self.terminal = true; Err(ControlError::IoFailure) }
        }
    }
}
