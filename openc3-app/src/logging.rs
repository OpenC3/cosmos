//! Structured JSON logging that matches the COSMOS logger format so openc3-app's
//! output is consistent with the rest of the system.
//!
//! Mirrors `build_log_data` in `openc3/lib/openc3/utilities/logger.rb`: every
//! line is a JSON object with `time` (nanoseconds since the epoch), `@timestamp`
//! (ISO8601 with 6 fractional digits, UTC), `level`, an optional
//! `microservice_name` (the component), `container_name` (the host name),
//! `message`, and `type` (always `log` here). Like COSMOS, everything goes to
//! stdout unless `OPENC3_LOG_STDERR` is set, in which case WARN/ERROR/FATAL go
//! to stderr.

use std::collections::VecDeque;
use std::io::Write;
use std::sync::{Mutex, OnceLock};

use serde::Serialize;

/// Most recent log records kept for the in-app log table.
const MAX_RECORDS: usize = 1000;

/// A captured log record for display in the GUI log table. Mirrors the JSON that
/// went to stdout so the table shows exactly what was logged.
#[derive(Clone)]
pub struct LogRecord {
    /// ISO8601 `@timestamp` string.
    pub timestamp: String,
    /// DEBUG / INFO / WARN / ERROR / FATAL.
    pub level: String,
    /// Component (`microservice_name`).
    pub source: String,
    pub message: String,
}

fn sink() -> &'static Mutex<VecDeque<LogRecord>> {
    static SINK: OnceLock<Mutex<VecDeque<LogRecord>>> = OnceLock::new();
    SINK.get_or_init(|| Mutex::new(VecDeque::with_capacity(MAX_RECORDS)))
}

fn push_record(record: LogRecord) {
    if let Ok(mut q) = sink().lock() {
        while q.len() >= MAX_RECORDS {
            q.pop_front();
        }
        q.push_back(record);
    }
}

/// Snapshot of the captured log records, oldest first.
pub fn snapshot() -> Vec<LogRecord> {
    sink()
        .lock()
        .map(|q| q.iter().cloned().collect())
        .unwrap_or_default()
}

/// Discard all captured log records (the GUI "clear log" action).
pub fn clear() {
    if let Ok(mut q) = sink().lock() {
        q.clear();
    }
}

/// The host name, resolved once. COSMOS uses `Socket.gethostname` for
/// `container_name`; on the host this is the machine name.
fn container_name() -> &'static str {
    static NAME: OnceLock<String> = OnceLock::new();
    NAME.get_or_init(|| gethostname::gethostname().to_string_lossy().into_owned())
}

/// True if `var` is set to a truthy value, matching COSMOS' `EnvHelper.enabled?`
/// (used for `OPENC3_LOG_STDERR`).
fn env_enabled(var: &str) -> bool {
    std::env::var(var)
        .map(|v| {
            let v = v.trim().to_ascii_lowercase();
            v == "1" || v == "true"
        })
        .unwrap_or(false)
}

/// One log record, serialized in COSMOS field order.
#[derive(Serialize)]
struct LogData<'a> {
    time: i64,
    #[serde(rename = "@timestamp")]
    timestamp: String,
    level: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    microservice_name: Option<&'a str>,
    container_name: &'a str,
    message: &'a str,
    #[serde(rename = "type")]
    log_type: &'a str,
}

fn emit(level: &str, name: Option<&str>, message: &str) {
    let now = chrono::Utc::now();
    let time_ns = now.timestamp_nanos_opt().unwrap_or(0);
    // 6 fractional digits to match the Ruby/Python `iso8601(6)` output.
    let timestamp = now.format("%Y-%m-%dT%H:%M:%S%.6fZ").to_string();
    let data = LogData {
        time: time_ns,
        timestamp: timestamp.clone(),
        level,
        microservice_name: name,
        container_name: container_name(),
        message,
        log_type: "log",
    };
    // Serialization of this fixed struct cannot realistically fail; fall back to
    // an empty line rather than panic so logging is never fatal.
    let line = serde_json::to_string(&data).unwrap_or_default();
    let to_stderr =
        matches!(level, "WARN" | "ERROR" | "FATAL") && env_enabled("OPENC3_LOG_STDERR");
    if to_stderr {
        let mut w = std::io::stderr().lock();
        let _ = writeln!(w, "{line}");
    } else {
        let mut w = std::io::stdout().lock();
        let _ = writeln!(w, "{line}");
    }
    push_record(LogRecord {
        timestamp,
        level: level.to_string(),
        source: name.unwrap_or("").to_string(),
        message: message.to_string(),
    });
}

/// Echo a pre-formatted log line to stdout/stderr and capture it for the log
/// table. Used for host-microservice output, which is already COSMOS JSON from
/// its own logger: JSON lines are parsed for their fields; anything else is
/// captured as a plain message attributed to `fallback_source`.
pub fn capture_line(line: &str, fallback_source: &str, stderr: bool) {
    if stderr {
        let mut w = std::io::stderr().lock();
        let _ = writeln!(w, "{line}");
    } else {
        let mut w = std::io::stdout().lock();
        let _ = writeln!(w, "{line}");
    }
    push_record(parse_line(line, fallback_source, stderr));
}

fn parse_line(line: &str, fallback_source: &str, stderr: bool) -> LogRecord {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
        if let (Some(level), Some(message)) = (
            v.get("level").and_then(|x| x.as_str()),
            v.get("message").and_then(|x| x.as_str()),
        ) {
            return LogRecord {
                timestamp: v.get("@timestamp").and_then(|x| x.as_str()).unwrap_or("").to_string(),
                level: level.to_string(),
                source: v
                    .get("microservice_name")
                    .and_then(|x| x.as_str())
                    .unwrap_or(fallback_source)
                    .to_string(),
                message: message.to_string(),
            };
        }
    }
    // Non-JSON (or non-log JSON) output: capture as plain text.
    let now = chrono::Utc::now();
    LogRecord {
        timestamp: now.format("%Y-%m-%dT%H:%M:%S%.6fZ").to_string(),
        level: if stderr { "WARN" } else { "INFO" }.to_string(),
        source: fallback_source.to_string(),
        message: line.to_string(),
    }
}

/// Log at INFO. `name` becomes the COSMOS `microservice_name` (the component).
pub fn info(name: &str, message: &str) {
    emit("INFO", Some(name), message);
}

/// Log at WARN.
pub fn warn(name: &str, message: &str) {
    emit("WARN", Some(name), message);
}

/// Log at ERROR.
pub fn error(name: &str, message: &str) {
    emit("ERROR", Some(name), message);
}

/// Log at DEBUG.
#[allow(dead_code)]
pub fn debug(name: &str, message: &str) {
    emit("DEBUG", Some(name), message);
}
