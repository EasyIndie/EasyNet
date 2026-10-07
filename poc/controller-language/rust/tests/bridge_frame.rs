use easynet_ssh_lab::{decode_frame, LabError};
use russh::keys::{Algorithm, PrivateKey, ssh_key::LineEnding};

fn key() -> PrivateKey {
    PrivateKey::random(&mut rand::rng(), Algorithm::Ed25519).expect("fixture key generation")
}
fn frame(id: &[u8], host: &[u8], private: &[u8]) -> Vec<u8> {
    let mut f = Vec::from(&b"ESLB1\n"[..]);
    f.extend_from_slice(&12345u16.to_be_bytes());
    f.extend_from_slice(&3000u32.to_be_bytes());
    f.extend_from_slice(&[0, id.len() as u8]);
    f.extend_from_slice(&(host.len() as u16).to_be_bytes());
    f.extend_from_slice(&(private.len() as u16).to_be_bytes());
    f.extend_from_slice(id);
    f.extend_from_slice(host);
    f.extend_from_slice(private);
    f
}
fn fixture() -> (Vec<u8>, Vec<u8>) {
    let host = key().public_key().to_bytes().expect("fixture public encoding");
    let private = key().to_openssh(LineEnding::LF).expect("fixture private encoding");
    (host, private.as_bytes().to_vec())
}
fn rejects(f: &[u8]) {
    match decode_frame(f) {
        Err(e) => {
            assert_eq!(e, LabError::InvalidInput);
            assert_eq!(e.to_string(), "invalid fixture input");
            assert_eq!(format!("{e:?}"), "InvalidInput");
        }
        Ok(_) => panic!("invalid fixture accepted"),
    }
}

#[test]
fn valid_ephemeral_keys_and_boundary_fields() {
    let (host, private) = fixture();
    for command in 0..=2 {
        let mut f = frame(&[b'_' ; 64], &host, &private);
        f[12] = command;
        let c = decode_frame(&f).expect("valid fixture decode");
        assert_eq!((c.port, c.deadline_ms, c.command), (12345, 3000, command));
        assert_eq!(c.operation_id.len(), 64);
        assert!(c.host_key.is_some());
        assert!(c.private_key.algorithm() == Algorithm::Ed25519);
    }
    let spaced = [b" \n".as_slice(), &private, b"\n\t"].concat();
    let mut f = frame(b"a-Z_09", &host, &spaced);
    f[6..8].copy_from_slice(&1u16.to_be_bytes());
    f[8..12].copy_from_slice(&1u32.to_be_bytes());
    assert!(decode_frame(&f).is_ok());
    let mut padded = private.clone();
    padded.resize(4096, b' ');
    assert!(decode_frame(&frame(b"op", &host, &padded)).is_ok());
    padded.push(b' ');
    rejects(&frame(b"op", &host, &padded));
}

#[test]
fn malformed_header_sizes_and_ids_reject_without_input_output() {
    let (host, private) = fixture();
    let valid = frame(b"op", &host, &private);
    for end in 0..valid.len() { rejects(&valid[..end]); }
    rejects(&[valid.as_slice(), b"x"].concat());
    rejects(&vec![0; 8193]);
    for (offset, replacement) in [(0, b'X'), (6, 0), (12, 3), (13, 0), (13, 65)] {
        let mut f = valid.clone();
        f[offset] = replacement;
        if offset == 6 { f[7] = 0; }
        rejects(&f);
    }
    for deadline in [0u32, 3001, u32::MAX] {
        let mut f = valid.clone(); f[8..12].copy_from_slice(&deadline.to_be_bytes()); rejects(&f);
    }
    for offset in [14, 16] {
        for len in [0u16, 65535] {
            let mut f = valid.clone(); f[offset..offset+2].copy_from_slice(&len.to_be_bytes()); rejects(&f);
        }
    }
    for id in [b"a b".as_slice(), b"a/b", &[0xff], b"", &[b'a'; 65]] {
        rejects(&frame(id, &host, &private));
    }
}

#[test]
fn key_formats_and_algorithms_reject() {
    let (host, private) = fixture();
    for invalid in [b"junk".as_slice(), &[0xff], host.as_slice()] {
        rejects(&frame(b"op", &host, invalid));
    }
    for invalid in [b"junk".as_slice(), private.as_slice()] {
        rejects(&frame(b"op", invalid, &private));
    }
    for invalid in [[b"preamble\n".as_slice(), &private].concat(),
        [private.as_slice(), b"junk"].concat(),
        [private.as_slice(), private.as_slice()].concat(),
        String::from_utf8(private.clone()).expect("fixture UTF8").replace("\n", "\r\n").into_bytes(),
        String::from_utf8(private.clone()).expect("fixture UTF8").replace(
            "PRIVATE KEY-----\n", "PRIVATE KEY-----\nHeader: value\n").into_bytes()] {
        rejects(&frame(b"op", &host, &invalid));
    }
    let other = PrivateKey::random(&mut rand::rng(), Algorithm::Ecdsa {
        curve: russh::keys::EcdsaCurve::NistP256 }).expect("fixture alternate key");
    let other_host = other.public_key().to_bytes().expect("fixture public encoding");
    let other_private = other.to_openssh(LineEnding::LF).expect("fixture private encoding");
    rejects(&frame(b"op", &other_host, &private));
    rejects(&frame(b"op", &host, other_private.as_bytes()));
    let encrypted = key().encrypt(&mut rand::rng(), b"fixture-only")
        .expect("fixture encryption").to_openssh(LineEnding::LF).expect("fixture encoding");
    rejects(&frame(b"op", &host, encrypted.as_bytes()));
}
