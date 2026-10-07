//! One fixed command on a borrowed, retained transport handle. Never retries.
use crate::transport::{ExpectedHost, TransportError};
use russh::{client::Handle, ChannelMsg};
use std::{future::Future, pin::Pin};
use tokio::time::Instant;

#[derive(Debug, PartialEq, Eq)]
pub enum Outcome { NotDispatched, Unknown, CompleteObserved }
pub struct ResultRecord {
    pub operation_id: String,
    pub outcome: Outcome,
    pub owner_retained: bool,
    pub output: Vec<u8>,
}
impl ResultRecord {
    pub fn new(operation_id: String) -> Self {
        Self { operation_id, outcome: Outcome::NotDispatched, owner_retained: false, output: Vec::new() }
    }
}
#[derive(Default)]
struct Observations { ack: bool, status: Option<u32>, stderr: usize, eof: bool }
impl Observations {
    // Returns true only for an explicit Close. None is not a close proof.
    fn observe(&mut self, msg: ChannelMsg, result: &mut ResultRecord) -> Result<bool, TransportError> {
        match msg {
            ChannelMsg::Success if !self.ack => self.ack = true,
            ChannelMsg::ExitStatus { exit_status } if self.status.is_none() => self.status = Some(exit_status),
            ChannelMsg::Data { data } => self.append(&data, false, result)?,
            ChannelMsg::ExtendedData { data, ext: 1 } => self.append(&data, true, result)?,
            ChannelMsg::Eof if !self.eof => self.eof = true,
            ChannelMsg::WindowAdjusted { .. } => {},
            ChannelMsg::Close => return Ok(true),
            _ => return Err(TransportError::Ssh),
        }
        Ok(false)
    }
    fn append(&mut self, data: &[u8], stderr: bool, result: &mut ResultRecord) -> Result<(), TransportError> {
        let room = 4096 - result.output.len();
        let retained = data.len().min(room);
        result.output.extend_from_slice(&data[..retained]);
        if stderr { self.stderr += retained; }
        if data.len() > room { return Err(TransportError::Ssh); }
        Ok(())
    }
    fn complete(&self, command: u8, result: &ResultRecord) -> bool {
        command == 0 && self.ack && self.status == Some(0) && self.stderr == 0
            && result.output == b"fixture complete\n"
    }
}

pub async fn run(
    handle: &mut Handle<ExpectedHost>, command: u8, result: &mut ResultRecord,
    deadline: Instant, mut cancel: Pin<&mut impl Future<Output = ()>>,
    mut acknowledged: impl FnMut() -> Result<(), TransportError>,
) -> Result<(), TransportError> {
    let command_text = match command {
        0 => "fixture.complete", 1 => "fixture.block", 2 => "fixture.large",
        _ => return Err(TransportError::InvalidState),
    };
    let mut channel = tokio::select! {
        biased;
        _ = &mut cancel => return Err(TransportError::Cancelled),
        _ = tokio::time::sleep_until(deadline) => return Err(TransportError::Deadline),
        opened = handle.channel_open_session() => opened.map_err(|_| TransportError::Ssh)?,
    };
    // This future sets ownership at its first poll, immediately before exec can
    // enqueue. Cancellation before that poll remains not-dispatched.
    {
        let exec = async {
            result.outcome = Outcome::Unknown;
            result.owner_retained = true;
            channel.exec(true, command_text).await.map_err(|_| TransportError::Ssh)
        };
        tokio::pin!(exec);
        tokio::select! {
            biased;
            _ = &mut cancel => return Err(TransportError::Cancelled),
            _ = tokio::time::sleep_until(deadline) => return Err(TransportError::Deadline),
            queued = &mut exec => queued?,
        }
    }
    let mut observations = Observations::default();
    loop {
        let msg = tokio::select! {
            biased;
            _ = &mut cancel => return Err(TransportError::Cancelled),
            _ = tokio::time::sleep_until(deadline) => return Err(TransportError::Deadline),
            msg = channel.wait() => msg.ok_or(TransportError::Ssh)?,
        };
        let was_ack = observations.ack;
        let closed = observations.observe(msg, result)?;
        if !was_ack && observations.ack { acknowledged()?; }
        if closed {
            if observations.complete(command, result) {
                result.outcome = Outcome::CompleteObserved;
                return Ok(());
            }
            return Err(TransportError::Ssh);
        }
    }
    // Every return drops channel/exec receiver before caller joins its owner.
}

#[cfg(test)]
mod tests {
    use super::*;
    fn dispatched() -> ResultRecord {
        let mut r = ResultRecord::new("fixture-op".into());
        r.outcome = Outcome::Unknown; r.owner_retained = true; r
    }
    #[test]
    fn mixed_output_boundary_preserves_owned_id() {
        let mut r = dispatched(); let mut o = Observations::default();
        o.append(&vec![b'o'; 2048], false, &mut r).unwrap();
        o.append(&vec![b'e'; 2048], true, &mut r).unwrap();
        assert_eq!(r.output.len(), 4096);
        assert_eq!(o.append(b"x", false, &mut r), Err(TransportError::Ssh));
        assert_eq!(r.output.len(), 4096); assert_eq!(r.operation_id, "fixture-op");
        assert_eq!(r.outcome, Outcome::Unknown); assert!(r.owner_retained);
    }
    #[test]
    fn complete_requires_ack_status_and_explicit_close() {
        let mut r = dispatched(); let mut o = Observations::default();
        o.append(b"fixture complete\n", false, &mut r).unwrap();
        assert!(!o.complete(0, &r));
        o.observe(ChannelMsg::Success, &mut r).unwrap();
        assert!(!o.complete(0, &r));
        o.observe(ChannelMsg::ExitStatus { exit_status: 0 }, &mut r).unwrap();
        // Predicate alone never transitions outcome. Only Close in run does.
        assert_eq!(r.outcome, Outcome::Unknown);
        assert!(o.observe(ChannelMsg::Close, &mut r).unwrap());
        assert!(o.complete(0, &r)); assert!(!o.complete(1, &r)); assert!(!o.complete(2, &r));
    }
    #[test]
    fn malformed_duplicate_and_stderr_are_conservative() {
        let mut r = dispatched(); let mut o = Observations::default();
        o.observe(ChannelMsg::Success, &mut r).unwrap();
        assert_eq!(o.observe(ChannelMsg::Success, &mut r), Err(TransportError::Ssh));
        o.observe(ChannelMsg::ExitStatus { exit_status: 0 }, &mut r).unwrap();
        assert_eq!(o.observe(ChannelMsg::ExitStatus { exit_status: 0 }, &mut r), Err(TransportError::Ssh));
        o.append(b"fixture complete\n", false, &mut r).unwrap();
        o.append(b"e", true, &mut r).unwrap(); assert!(!o.complete(0, &r));
        assert_eq!(o.observe(ChannelMsg::ExtendedData { data: Vec::new().into(), ext: 2 }, &mut r), Err(TransportError::Ssh));
        assert_eq!(o.observe(ChannelMsg::Failure, &mut r), Err(TransportError::Ssh));
    }
}
