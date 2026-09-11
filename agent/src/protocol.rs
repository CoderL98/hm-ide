//! JSON-RPC-ish protocol types for hm-ide-agent.

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const AGENT_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const PROTOCOL_ID: &str = "hm-ide-remote/0.2";

#[derive(Debug, Clone, Deserialize)]
pub struct RpcRequest {
    pub id: Option<Value>,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct RpcSuccess {
    pub id: Value,
    pub result: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct RpcErrorBody {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RpcError {
    pub id: Value,
    pub error: RpcErrorBody,
}

#[derive(Debug, Clone, Serialize)]
pub struct RpcNotification {
    pub method: String,
    pub params: Value,
}

pub fn ok(id: Value, result: Value) -> String {
    serde_json::to_string(&RpcSuccess { id, result }).unwrap_or_else(|_| {
        r#"{"id":null,"error":{"code":-32603,"message":"serialize failed"}}"#.into()
    })
}

pub fn err(id: Value, code: i32, message: impl Into<String>) -> String {
    serde_json::to_string(&RpcError {
        id,
        error: RpcErrorBody {
            code,
            message: message.into(),
            data: None,
        },
    })
    .unwrap_or_else(|_| {
        r#"{"id":null,"error":{"code":-32603,"message":"serialize failed"}}"#.into()
    })
}

pub fn notify(method: &str, params: Value) -> String {
    serde_json::to_string(&RpcNotification {
        method: method.into(),
        params,
    })
    .unwrap_or_default()
}

#[derive(Debug, Clone, Serialize)]
pub struct HelloResult {
    pub version: String,
    pub os: String,
    pub arch: String,
    pub pid: u32,
    pub protocol: String,
    /// Stable session token for reconnect/resume
    pub session_token: String,
    pub resumed: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct FsEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: u64,
    pub mtime_ms: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct FsStat {
    pub path: String,
    pub is_dir: bool,
    pub is_file: bool,
    pub size: u64,
    pub mtime_ms: u64,
    pub mode: u32,
}
