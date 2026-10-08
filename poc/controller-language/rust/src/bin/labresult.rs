//! Bounded, redacted candidate summary; no SSH or vault operations.
use easynet_ssh_lab::ssh_run::{Outcome, ResultRecord};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde::de::{self, MapAccess, Visitor};
use serde::ser::SerializeStruct;
use serde_json::value::RawValue;
use std::{fmt, io::{self, Read, Write}};

#[derive(Debug, PartialEq, Eq)]
enum Error { InvalidLabRecord, LabRecordIO }
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::InvalidLabRecord => "invalid lab record",
            Self::LabRecordIO => "lab record I/O failure",
        })
    }
}
impl std::error::Error for Error {}
#[derive(Debug, PartialEq, Eq)]
struct LabRecord {
    kind: String, schema_version: usize, operation_id: String,
    outcome: String, owner_retained: bool, output_bytes: usize,
}
impl LabRecord {
    fn valid(&self) -> bool {
        self.kind == "easynet-lab-result" && self.schema_version == 1
            && (1..=64).contains(&self.operation_id.len())
            && self.operation_id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
            && self.output_bytes <= 4096 && match self.outcome.as_str() {
                "not-dispatched" => !self.owner_retained && self.output_bytes == 0,
                "unknown" | "fixture-complete-observed" => self.owner_retained,
                _ => false,
            }
    }
}
// Kept private to this candidate binary; borrowing never changes result ownership.
#[allow(dead_code)]
fn summarize(result: &ResultRecord) -> Result<LabRecord, Error> {
    let record = LabRecord {
        kind: "easynet-lab-result".into(), schema_version: 1,
        operation_id: result.operation_id.clone(),
        outcome: match result.outcome {
            Outcome::NotDispatched => "not-dispatched",
            Outcome::Unknown => "unknown",
            Outcome::CompleteObserved => "fixture-complete-observed",
        }.into(),
        owner_retained: result.owner_retained, output_bytes: result.output.len(),
    };
    if record.valid() { Ok(record) } else { Err(Error::InvalidLabRecord) }
}
impl<'de> Deserialize<'de> for LabRecord {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct RecordVisitor;
        impl<'de> Visitor<'de> for RecordVisitor {
            type Value = LabRecord;
            fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { f.write_str("lab record") }
            fn visit_map<M: MapAccess<'de>>(self, mut map: M) -> Result<LabRecord, M::Error> {
                let mut fields: [Option<&'de RawValue>; 6] = [None; 6];
                while let Some(key) = map.next_key::<String>()? {
                    let index = match key.as_str() {
                        "kind" => 0, "schemaVersion" => 1, "operationId" => 2,
                        "outcome" => 3, "ownerRetained" => 4, "outputBytes" => 5,
                        _ => return Err(de::Error::custom("invalid lab record")),
                    };
                    if fields[index].is_some() { return Err(de::Error::custom("invalid lab record")); }
                    fields[index] = Some(map.next_value::<&RawValue>()?);
                }
                let bad = || de::Error::custom("invalid lab record");
                let mut raw = [""; 6];
                for (i, field) in fields.into_iter().enumerate() { raw[i] = field.ok_or_else(bad)?.get(); }
                if raw[1] != "1" { return Err(bad()); }
                let number = raw[5].as_bytes();
                if !(number == b"0" || (!number.is_empty() && (b'1'..=b'9').contains(&number[0])
                    && number.iter().all(u8::is_ascii_digit))) { return Err(bad()); }
                let record = LabRecord {
                    kind: serde_json::from_str(raw[0]).map_err(|_| bad())?, schema_version: 1,
                    operation_id: serde_json::from_str(raw[2]).map_err(|_| bad())?,
                    outcome: serde_json::from_str(raw[3]).map_err(|_| bad())?,
                    owner_retained: serde_json::from_str(raw[4]).map_err(|_| bad())?,
                    output_bytes: raw[5].parse().map_err(|_| bad())?,
                };
                if record.valid() { Ok(record) } else { Err(bad()) }
            }
        }
        d.deserialize_map(RecordVisitor)
    }
}
impl Serialize for LabRecord {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut obj = s.serialize_struct("LabRecord", 6)?;
        obj.serialize_field("kind", &self.kind)?;
        obj.serialize_field("schemaVersion", &self.schema_version)?;
        obj.serialize_field("operationId", &self.operation_id)?;
        obj.serialize_field("outcome", &self.outcome)?;
        obj.serialize_field("ownerRetained", &self.owner_retained)?;
        obj.serialize_field("outputBytes", &self.output_bytes)?;
        obj.end()
    }
}
fn decode(reader: impl Read) -> Result<LabRecord, Error> {
    let mut data = Vec::new();
    reader.take(4097).read_to_end(&mut data).map_err(|_| Error::LabRecordIO)?;
    if data.len() > 4096 { return Err(Error::InvalidLabRecord); }
    let text = std::str::from_utf8(&data).map_err(|_| Error::InvalidLabRecord)?;
    let mut parser = serde_json::Deserializer::from_str(text);
    let record = LabRecord::deserialize(&mut parser).map_err(|_| Error::InvalidLabRecord)?;
    parser.end().map_err(|_| Error::InvalidLabRecord)?;
    Ok(record)
}
fn encode(mut writer: impl Write, record: &LabRecord) -> Result<(), Error> {
    if !record.valid() { return Err(Error::InvalidLabRecord); }
    let data = serde_json::to_vec(record).map_err(|_| Error::InvalidLabRecord)?;
    if writer.write(&data).map_err(|_| Error::LabRecordIO)? != data.len() { return Err(Error::LabRecordIO); }
    Ok(()) // One write may be partial on failure; delivery is not atomic.
}
fn run(has_args: bool, input: impl Read, output: impl Write, mut diagnostic: impl Write) -> i32 {
    let result = if has_args { Err("invalid lab arguments") } else {
        decode(input).map_err(|e| match e {
            Error::InvalidLabRecord => "invalid lab input", Error::LabRecordIO => "lab I/O failure",
        }).and_then(|r| encode(output, &r).map_err(|_| "lab I/O failure"))
    };
    match result { Ok(()) => 0, Err(message) => { let _ = writeln!(diagnostic, "{message}"); 2 } }
}
fn main() {
    std::process::exit(run(std::env::args_os().nth(1).is_some(), io::stdin().lock(), io::stdout().lock(), io::stderr().lock()));
}
#[cfg(test)]
mod tests {
    use super::*;
    const RECORD: &str = r#"{"kind":"easynet-lab-result","schemaVersion":1,"operationId":"fixture_1","outcome":"unknown","ownerRetained":true,"outputBytes":4}"#;
    #[test]
    fn exact_contract() {
        let r = decode(RECORD.as_bytes()).unwrap();
        let mut out = Vec::new(); encode(&mut out, &r).unwrap(); assert_eq!(out, RECORD.as_bytes());
        for (old, values) in [
            ("\"schemaVersion\":1", vec!["1.0", "1e0", "2", "null", "true", "\"1\"", "{}"]),
            ("\"outputBytes\":4", vec!["-0", "4.0", "4e0", "4097", "184467440737095516160", "null", "[]", "\"4\""]),
        ] {
            for value in values { let key = old.split(':').next().unwrap();
                assert_eq!(decode(RECORD.replace(old, &format!("{key}:{value}")).as_bytes()), Err(Error::InvalidLabRecord)); }
        }
        for key in ["Kind", "extra", "k\\u0069nd"] {
            assert_eq!(decode(RECORD.replacen("\"kind\":", &format!("\"{key}\":\"easynet-lab-result\",\"kind\":"), 1).as_bytes()), Err(Error::InvalidLabRecord));
        }
        for text in ["[]".into(), "{}".into(), format!("{RECORD}{{}}"), RECORD.replace("fixture_1", "秘密"),
            RECORD.replace("\"ownerRetained\":true", "\"ownerRetained\":false"), RECORD.replace(",\"outputBytes\":4", "")] {
            assert_eq!(decode(text.as_bytes()), Err(Error::InvalidLabRecord));
        }
        let mut boundary = RECORD.as_bytes().to_vec(); boundary.resize(4096, b' '); assert!(decode(&boundary[..]).is_ok());
        boundary.push(b' '); assert_eq!(decode(&boundary[..]), Err(Error::InvalidLabRecord));
        assert_eq!(decode(&[0xff][..]), Err(Error::InvalidLabRecord));
    }
    #[test]
    fn summarize_validates_and_preserves() {
        let mut source = ResultRecord::new("fixture_1".into());
        assert!(summarize(&source).is_ok());
        source.outcome = Outcome::Unknown; source.owner_retained = true; source.output = "秘密".as_bytes().to_vec();
        assert_eq!(summarize(&source).unwrap().output_bytes, 6); assert!(source.owner_retained);
        source.outcome = Outcome::CompleteObserved; assert!(summarize(&source).unwrap().owner_retained);
        source.owner_retained = false; assert_eq!(summarize(&source), Err(Error::InvalidLabRecord));
        source.owner_retained = true; source.operation_id = "x".repeat(64); source.output.resize(4096, 0); assert!(summarize(&source).is_ok());
        source.output.push(0); assert_eq!(summarize(&source), Err(Error::InvalidLabRecord));
        source.output.clear(); source.operation_id.push('x'); assert_eq!(summarize(&source), Err(Error::InvalidLabRecord));
        source.operation_id.clear(); assert_eq!(summarize(&source), Err(Error::InvalidLabRecord));
        source.operation_id = "bad/id".into(); assert_eq!(summarize(&source), Err(Error::InvalidLabRecord));
        source.operation_id = "ok".into(); source.outcome = Outcome::NotDispatched; assert_eq!(summarize(&source), Err(Error::InvalidLabRecord));
        source.owner_retained = false; source.output.push(1); assert_eq!(summarize(&source), Err(Error::InvalidLabRecord));
    }
    struct Fail;
    impl Read for Fail { fn read(&mut self, _: &mut [u8]) -> io::Result<usize> { Err(io::Error::other("fixture-secret")) } }
    struct BadWriter(bool);
    impl Write for BadWriter {
        fn write(&mut self, b: &[u8]) -> io::Result<usize> { if self.0 { Ok(b.len()-1) } else { Err(io::Error::other("fixture-secret")) } }
        fn flush(&mut self) -> io::Result<()> { Ok(()) }
    }
    #[test]
    fn fixed_io_errors_and_prevalidation() {
        assert_eq!(decode(Fail), Err(Error::LabRecordIO));
        let mut diagnostic = Vec::new(); assert_eq!(run(false, Fail, Vec::new(), &mut diagnostic), 2);
        assert_eq!(diagnostic, b"lab I/O failure\n");
        for short in [false, true] {
            diagnostic.clear(); assert_eq!(run(false, RECORD.as_bytes(), BadWriter(short), &mut diagnostic), 2);
            assert_eq!(diagnostic, b"lab I/O failure\n");
        }
        let mut r = decode(RECORD.as_bytes()).unwrap(); r.operation_id.clear();
        let mut out = Vec::new(); assert_eq!(encode(&mut out, &r), Err(Error::InvalidLabRecord)); assert!(out.is_empty());
    }
}
