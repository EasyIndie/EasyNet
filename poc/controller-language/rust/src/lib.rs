//! Memory-only credential framing for the isolated Rust SSH lab.
use russh::keys::{Algorithm, PrivateKey, PublicKey};

pub struct Credentials {
    pub port: u16,
    pub deadline_ms: u32,
    pub command: u8,
    pub operation_id: String,
    pub host_key: Option<PublicKey>,
    pub private_key: PrivateKey,
}

#[derive(Debug, PartialEq, Eq)]
pub enum LabError {
    InvalidInput,
}
impl std::fmt::Display for LabError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("invalid fixture input")
    }
}
impl std::error::Error for LabError {}

pub fn decode_frame(frame: &[u8]) -> Result<Credentials, LabError> {
    let bad = LabError::InvalidInput;
    if frame.len() < 18 || frame.len() > 8192 || &frame[..6] != b"ESLB1\n" {
        return Err(bad);
    }
    let port = u16::from_be_bytes([frame[6], frame[7]]);
    let deadline_ms = u32::from_be_bytes([frame[8], frame[9], frame[10], frame[11]]);
    let command = frame[12];
    let id_len = usize::from(frame[13]);
    let host_len = usize::from(u16::from_be_bytes([frame[14], frame[15]]));
    let key_len = usize::from(u16::from_be_bytes([frame[16], frame[17]]));
    if port == 0 || !(1..=3000).contains(&deadline_ms) || command > 2
        || !(1..=64).contains(&id_len) || !(1..=256).contains(&host_len)
        || !(1..=4096).contains(&key_len) {
        return Err(bad);
    }
    let host_start = 18usize.checked_add(id_len).ok_or(LabError::InvalidInput)?;
    let key_start = host_start.checked_add(host_len).ok_or(LabError::InvalidInput)?;
    let end = key_start.checked_add(key_len).ok_or(LabError::InvalidInput)?;
    if end != frame.len() {
        return Err(bad);
    }
    let id = &frame[18..host_start];
    if !id.iter().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-')) {
        return Err(bad);
    }
    let operation_id = std::str::from_utf8(id).map_err(|_| LabError::InvalidInput)?.to_owned();
    let host_key = PublicKey::from_bytes(&frame[host_start..key_start])
        .map_err(|_| LabError::InvalidInput)?;
    let text = std::str::from_utf8(&frame[key_start..]).map_err(|_| LabError::InvalidInput)?;
    let text = text.trim();
    if !text.starts_with("-----BEGIN OPENSSH PRIVATE KEY-----\n")
        || !text.ends_with("-----END OPENSSH PRIVATE KEY-----") {
        return Err(bad);
    }
    let private_key = PrivateKey::from_openssh(text).map_err(|_| LabError::InvalidInput)?;
    if host_key.algorithm() != Algorithm::Ed25519 || private_key.is_encrypted()
        || private_key.algorithm() != Algorithm::Ed25519 {
        return Err(bad);
    }
    Ok(Credentials { port, deadline_ms, command, operation_id,
        host_key: Some(host_key), private_key })
}
