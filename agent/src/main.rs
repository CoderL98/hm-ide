//! hm-ide-agent — remote FS + PTY + watch/search/git/task over WebSocket JSON-RPC.
//! Binds 127.0.0.1 only; IDE reaches it via SSH LocalForward.

mod fs_ops;
mod git_ops;
mod protocol;
mod pty_mgr;
mod search_ops;
mod task_mgr;
mod watch_mgr;

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use clap::Parser;
use futures_util::{SinkExt, StreamExt};
use protocol::{err, notify, ok, HelloResult, AGENT_VERSION, PROTOCOL_ID};
use pty_mgr::PtyManager;
use serde::Deserialize;
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use task_mgr::SharedTaskManager;
use tokio::sync::{mpsc, Mutex};
use tower_http::cors::CorsLayer;
use tracing::{info, warn};
use uuid::Uuid;
use watch_mgr::WatchManager;

#[derive(Parser, Debug)]
#[command(name = "hm-ide-agent", about = "HM-IDE remote agent (Scheme B)", version = AGENT_VERSION)]
struct Args {
    /// Listen port (always bind 127.0.0.1)
    #[arg(long, default_value_t = 17821)]
    port: u16,

    /// Optional bearer token; if set, clients must pass ?token=
    #[arg(long)]
    token: Option<String>,

    /// Replace current binary with this path then exit (caller restarts)
    #[arg(long)]
    self_upgrade: Option<PathBuf>,
}

#[derive(Clone)]
struct AppState {
    token: Option<String>,
    pty: Arc<PtyManager>,
    watch: Arc<WatchManager>,
    tasks: Arc<SharedTaskManager>,
    /// Last issued session token (for optional resume)
    session_token: Arc<Mutex<String>>,
}

#[derive(Debug, Deserialize)]
struct WsQuery {
    token: Option<String>,
}

#[derive(Debug, Deserialize)]
struct UpgradeBody {
    /// Absolute path to new binary already uploaded (e.g. ~/.hm-ide-agent/bin/hm-ide-agent.new)
    path: String,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "hm_ide_agent=info".into()),
        )
        .init();

    let args = Args::parse();

    if let Some(ref new_bin) = args.self_upgrade {
        return do_self_upgrade(new_bin);
    }

    let state = AppState {
        token: args.token.clone(),
        pty: Arc::new(PtyManager::new()),
        watch: Arc::new(WatchManager::new()),
        tasks: Arc::new(SharedTaskManager::new()),
        session_token: Arc::new(Mutex::new(Uuid::new_v4().to_string())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/upgrade", post(upgrade_handler))
        .route("/ws", get(ws_handler))
        .route("/", get(ws_handler))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], args.port));
    info!(
        "hm-ide-agent v{} listening on ws://{}/ws (loopback only)",
        AGENT_VERSION, addr
    );
    if args.token.is_some() {
        info!("token auth enabled");
    }

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

fn do_self_upgrade(new_bin: &PathBuf) -> anyhow::Result<()> {
    use std::fs;
    let current = std::env::current_exe()?;
    info!("self-upgrade: {:?} -> {:?}", new_bin, current);
    if !new_bin.exists() {
        anyhow::bail!("new binary not found: {}", new_bin.display());
    }
    let backup = current.with_extension("bak");
    let _ = fs::remove_file(&backup);
    if current.exists() {
        fs::rename(&current, &backup)?;
    }
    fs::copy(new_bin, &current)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&current)?.permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&current, perms)?;
    }
    info!("self-upgrade done; exiting so supervisor can restart");
    Ok(())
}

async fn health() -> impl IntoResponse {
    axum::Json(json!({
        "ok": true,
        "version": AGENT_VERSION,
        "protocol": PROTOCOL_ID,
        "pid": std::process::id(),
    }))
}

async fn upgrade_handler(
    State(_state): State<AppState>,
    Json(body): Json<UpgradeBody>,
) -> impl IntoResponse {
    let path = PathBuf::from(&body.path);
    match do_self_upgrade(&path) {
        Ok(()) => {
            // Schedule exit so HTTP response can flush
            tokio::spawn(async {
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                std::process::exit(0);
            });
            (
                axum::http::StatusCode::OK,
                Json(json!({ "ok": true, "message": "upgraded; exiting" })),
            )
        }
        Err(e) => (
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({ "ok": false, "message": e.to_string() })),
        ),
    }
}

async fn ws_handler(
    ws: WebSocketUpgrade,
    Query(q): Query<WsQuery>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    if let Some(ref expected) = state.token {
        let ok_tok = q.token.as_ref().map(|t| t == expected).unwrap_or(false);
        if !ok_tok {
            return (
                axum::http::StatusCode::UNAUTHORIZED,
                "missing or invalid token",
            )
                .into_response();
        }
    }
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: AppState) {
    let (tx_ws, mut rx_ws) = socket.split();
    let tx_ws = Arc::new(Mutex::new(tx_ws));

    let (pty_data_tx, mut pty_data_rx) = mpsc::unbounded_channel::<(String, Vec<u8>)>();
    let (fs_changed_tx, mut fs_changed_rx) = mpsc::unbounded_channel::<(String, Value)>();
    let (task_event_tx, mut task_event_rx) = mpsc::unbounded_channel::<(String, Value)>();

    let tx_notify = tx_ws.clone();
    let notify_task = tokio::spawn(async move {
        loop {
            tokio::select! {
                Some((pty_id, data)) = pty_data_rx.recv() => {
                    use base64::{engine::general_purpose::STANDARD, Engine};
                    let msg = if data.is_empty() {
                        notify("pty.exit", json!({ "ptyId": pty_id }))
                    } else {
                        let params = match String::from_utf8(data.clone()) {
                            Ok(s) => json!({ "ptyId": pty_id, "encoding": "utf8", "data": s }),
                            Err(_) => json!({
                                "ptyId": pty_id,
                                "encoding": "base64",
                                "data": STANDARD.encode(&data)
                            }),
                        };
                        notify("pty.data", params)
                    };
                    let mut sink = tx_notify.lock().await;
                    if sink.send(Message::Text(msg)).await.is_err() {
                        break;
                    }
                }
                Some((_wid, params)) = fs_changed_rx.recv() => {
                    let msg = notify("fs.changed", params);
                    let mut sink = tx_notify.lock().await;
                    if sink.send(Message::Text(msg)).await.is_err() {
                        break;
                    }
                }
                Some((_tid, params)) = task_event_rx.recv() => {
                    let is_exit = params.get("_event").and_then(|v| v.as_str()) == Some("exit");
                    let method = if is_exit { "task.exit" } else { "task.output" };
                    let mut clean = params.clone();
                    if let Some(obj) = clean.as_object_mut() {
                        obj.remove("_event");
                    }
                    let msg = notify(method, clean);
                    let mut sink = tx_notify.lock().await;
                    if sink.send(Message::Text(msg)).await.is_err() {
                        break;
                    }
                }
                else => break,
            }
        }
    });

    while let Some(Ok(msg)) = rx_ws.next().await {
        match msg {
            Message::Text(text) => {
                let reply = dispatch(
                    &text,
                    &state,
                    pty_data_tx.clone(),
                    fs_changed_tx.clone(),
                    task_event_tx.clone(),
                )
                .await;
                if let Some(r) = reply {
                    let mut sink = tx_ws.lock().await;
                    if sink.send(Message::Text(r)).await.is_err() {
                        break;
                    }
                }
            }
            Message::Ping(p) => {
                let mut sink = tx_ws.lock().await;
                let _ = sink.send(Message::Pong(p)).await;
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    notify_task.abort();
    info!("websocket closed");
}

async fn dispatch(
    text: &str,
    state: &AppState,
    pty_data_tx: mpsc::UnboundedSender<(String, Vec<u8>)>,
    fs_changed_tx: mpsc::UnboundedSender<(String, Value)>,
    task_event_tx: mpsc::UnboundedSender<(String, Value)>,
) -> Option<String> {
    let req: protocol::RpcRequest = match serde_json::from_str(text) {
        Ok(r) => r,
        Err(e) => {
            return Some(err(Value::Null, -32700, format!("parse error: {e}")));
        }
    };

    let id = req.id.clone().unwrap_or(Value::Null);
    let method = req.method.as_str();
    let params = &req.params;

    let result: Result<Value, anyhow::Error> = match method {
        "session.hello" => {
            let resume = params
                .get("sessionToken")
                .or_else(|| params.get("session_token"))
                .and_then(|v| v.as_str());
            let mut guard = state.session_token.lock().await;
            let resumed = if let Some(tok) = resume {
                if tok == guard.as_str() {
                    true
                } else {
                    *guard = Uuid::new_v4().to_string();
                    false
                }
            } else {
                *guard = Uuid::new_v4().to_string();
                false
            };
            let hello = HelloResult {
                version: AGENT_VERSION.to_string(),
                os: std::env::consts::OS.to_string(),
                arch: std::env::consts::ARCH.to_string(),
                pid: std::process::id(),
                protocol: PROTOCOL_ID.to_string(),
                session_token: guard.clone(),
                resumed,
            };
            Ok(serde_json::to_value(hello).unwrap())
        }
        "fs.list" => fs_ops::list(params),
        "fs.read" => fs_ops::read(params),
        "fs.write" => fs_ops::write(params),
        "fs.mkdir" => fs_ops::mkdir(params),
        "fs.remove" => fs_ops::remove(params),
        "fs.rename" => fs_ops::rename(params),
        "fs.stat" => fs_ops::stat(params),
        "fs.search" => search_ops::search(params),
        "fs.watch" => state.watch.watch(params, fs_changed_tx),
        "fs.unwatch" => state.watch.unwatch(params),
        "git.status" => git_ops::status(params),
        "git.diff" => git_ops::diff_summary(params),
        "task.run" => state.tasks.run(params, task_event_tx).await,
        "task.kill" => state.tasks.kill(params),
        "agent.upgrade" => {
            // params: { path: "/path/to/new/binary" } — replaces exe and exits
            match params.get("path").and_then(|v| v.as_str()) {
                None => Err(anyhow::anyhow!("missing path")),
                Some(path) => {
                    let pb = PathBuf::from(path);
                    match do_self_upgrade(&pb) {
                        Ok(()) => {
                            tokio::spawn(async {
                                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                                std::process::exit(0);
                            });
                            Ok(json!({ "ok": true, "message": "upgraded; exiting" }))
                        }
                        Err(e) => Err(e),
                    }
                }
            }
        }
        "pty.open" => state.pty.open_params(params, pty_data_tx),
        "pty.write" => {
            let pty_id = match params.get("ptyId").and_then(|v| v.as_str()) {
                Some(p) => p,
                None => return Some(err(id, -32602, "missing ptyId")),
            };
            let encoding = params
                .get("encoding")
                .and_then(|v| v.as_str())
                .unwrap_or("utf8");
            let data_str = params.get("data").and_then(|v| v.as_str()).unwrap_or("");
            let bytes: Result<Vec<u8>, anyhow::Error> = if encoding == "base64" {
                use base64::{engine::general_purpose::STANDARD, Engine};
                STANDARD
                    .decode(data_str)
                    .map_err(|e| anyhow::anyhow!("base64: {e}"))
            } else {
                Ok(data_str.as_bytes().to_vec())
            };
            match bytes {
                Ok(b) => state.pty.write(pty_id, &b).map(|_| json!({ "ok": true })),
                Err(e) => Err(e),
            }
        }
        "pty.resize" => {
            let pty_id = match params.get("ptyId").and_then(|v| v.as_str()) {
                Some(p) => p,
                None => return Some(err(id, -32602, "missing ptyId")),
            };
            let cols = params.get("cols").and_then(|v| v.as_u64()).unwrap_or(80) as u16;
            let rows = params.get("rows").and_then(|v| v.as_u64()).unwrap_or(24) as u16;
            state
                .pty
                .resize(pty_id, cols, rows)
                .map(|_| json!({ "ok": true }))
        }
        "pty.close" => {
            let pty_id = match params.get("ptyId").and_then(|v| v.as_str()) {
                Some(p) => p,
                None => return Some(err(id, -32602, "missing ptyId")),
            };
            state.pty.close(pty_id).map(|_| json!({ "ok": true }))
        }
        _ => {
            warn!("unknown method: {method}");
            return Some(err(id, -32601, format!("method not found: {method}")));
        }
    };

    match result {
        Ok(v) => Some(ok(id, v)),
        Err(e) => Some(err(id, -32000, e.to_string())),
    }
}
