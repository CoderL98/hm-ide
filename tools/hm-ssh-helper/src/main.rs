//! Desktop SSH helper for hm-ide auto-deploy.
//! Steps: detect arch → SFTP upload → remote install → start agent → LocalForward.
//! Prefer OpenSSH `ssh`/`scp` when available; fall back to libssh2 (ssh2 crate).

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use ssh2::Session;
use std::fs::File;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

#[derive(Parser, Debug)]
#[command(name = "hm-ssh-helper", version, about = "HM-IDE SSH deploy helper (desktop)")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Full auto-deploy + optional LocalForward
    Deploy {
        #[arg(long)]
        host: String,
        #[arg(long, default_value_t = 22)]
        port: u16,
        #[arg(long)]
        user: String,
        #[arg(long)]
        identity: Option<PathBuf>,
        #[arg(long)]
        password: Option<String>,
        #[arg(long, default_value = "")]
        remote_path: String,
        #[arg(long, default_value_t = 17821)]
        agent_port: u16,
        #[arg(long, default_value = "")]
        token: String,
        #[arg(long)]
        binary: Option<PathBuf>,
        #[arg(long, default_value_t = false)]
        force: bool,
        /// Do not open LocalForward (upload+start only)
        #[arg(long, default_value_t = false)]
        no_forward: bool,
        /// Prefer OpenSSH CLI when present
        #[arg(long, default_value_t = true)]
        prefer_openssh: bool,
    },
    /// Detect remote uname -m
    DetectArch {
        #[arg(long)]
        host: String,
        #[arg(long, default_value_t = 22)]
        port: u16,
        #[arg(long)]
        user: String,
        #[arg(long)]
        identity: Option<PathBuf>,
        #[arg(long)]
        password: Option<String>,
    },
    /// Replace binary + restart only
    Upgrade {
        #[arg(long)]
        host: String,
        #[arg(long, default_value_t = 22)]
        port: u16,
        #[arg(long)]
        user: String,
        #[arg(long)]
        identity: Option<PathBuf>,
        #[arg(long)]
        password: Option<String>,
        #[arg(long, default_value_t = 17821)]
        agent_port: u16,
        #[arg(long)]
        binary: PathBuf,
        #[arg(long, default_value = "")]
        token: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Deploy {
            host,
            port,
            user,
            identity,
            password,
            remote_path,
            agent_port,
            token,
            binary,
            force,
            no_forward,
            prefer_openssh,
        } => {
            let forward = !no_forward;
            if prefer_openssh && which("ssh") && which("scp") {
                deploy_openssh(
                    &host,
                    port,
                    &user,
                    identity.as_deref(),
                    &remote_path,
                    agent_port,
                    &token,
                    binary.as_deref(),
                    force,
                    forward,
                )
            } else {
                deploy_libssh2(
                    &host,
                    port,
                    &user,
                    identity.as_deref(),
                    password.as_deref(),
                    &remote_path,
                    agent_port,
                    &token,
                    binary.as_deref(),
                    force,
                    forward,
                )
            }
        }
        Cmd::DetectArch {
            host,
            port,
            user,
            identity,
            password,
        } => {
            let arch = if which("ssh") {
                ssh_exec_openssh(&host, port, &user, identity.as_deref(), "uname -m")?
            } else {
                let sess = connect_ssh2(&host, port, &user, identity.as_deref(), password.as_deref())?;
                ssh2_exec(&sess, "uname -m")?
            };
            let arch = arch.trim().to_string();
            let tag = arch_tag(&arch)?;
            println!("{}", serde_json::json!({ "arch": arch, "tag": tag }));
            Ok(())
        }
        Cmd::Upgrade {
            host,
            port,
            user,
            identity,
            password,
            agent_port,
            binary,
            token,
        } => {
            if which("ssh") && which("scp") {
                deploy_openssh(
                    &host,
                    port,
                    &user,
                    identity.as_deref(),
                    "",
                    agent_port,
                    &token,
                    Some(&binary),
                    true,
                    false,
                )
            } else {
                deploy_libssh2(
                    &host,
                    port,
                    &user,
                    identity.as_deref(),
                    password.as_deref(),
                    "",
                    agent_port,
                    &token,
                    Some(&binary),
                    true,
                    false,
                )
            }
        }
    }
}

fn which(bin: &str) -> bool {
    Command::new("which")
        .arg(bin)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn arch_tag(arch: &str) -> Result<&'static str> {
    match arch {
        "x86_64" | "amd64" => Ok("x86_64"),
        "aarch64" | "arm64" => Ok("aarch64"),
        _ => Err(anyhow!("unsupported remote arch: {arch}")),
    }
}

fn default_binary(tag: &str) -> PathBuf {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf();
    root.join(format!("agent/dist/hm-ide-agent-{tag}-linux"))
}

fn progress(step: &str, msg: &str) {
    println!("[{step}] {msg}");
    let _ = std::io::stdout().flush();
}

fn ssh_exec_openssh(
    host: &str,
    port: u16,
    user: &str,
    identity: Option<&Path>,
    cmd: &str,
) -> Result<String> {
    let mut c = Command::new("ssh");
    c.arg("-p").arg(port.to_string());
    c.arg("-o").arg("StrictHostKeyChecking=accept-new");
    c.arg("-o").arg("BatchMode=yes");
    if let Some(id) = identity {
        c.arg("-i").arg(id);
    }
    c.arg(format!("{user}@{host}")).arg(cmd);
    let out = c.output().context("ssh failed")?;
    if !out.status.success() {
        return Err(anyhow!(
            "ssh error: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

fn deploy_openssh(
    host: &str,
    port: u16,
    user: &str,
    identity: Option<&Path>,
    remote_path: &str,
    agent_port: u16,
    token: &str,
    binary: Option<&Path>,
    force: bool,
    forward: bool,
) -> Result<()> {
    progress("detect", "detecting remote arch via ssh…");
    let arch = ssh_exec_openssh(host, port, user, identity, "uname -m")?;
    let tag = arch_tag(arch.trim())?;
    let bin = binary
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| default_binary(tag));
    if !bin.is_file() {
        return Err(anyhow!("missing binary: {}", bin.display()));
    }
    progress("detect", &format!("arch={tag} binary={}", bin.display()));

    let target = format!("{user}@{host}");
    let remote_dir = "$HOME/.hm-ide-agent/bin";
    let remote_bin = "$HOME/.hm-ide-agent/bin/hm-ide-agent";

    progress("mkdir", "ensuring remote install dir…");
    ssh_exec_openssh(host, port, user, identity, &format!("mkdir -p {remote_dir}"))?;

    let mut need_upload = force;
    if !need_upload {
        let exists = ssh_exec_openssh(
            host,
            port,
            user,
            identity,
            &format!("test -x {remote_bin} && echo YES || echo NO"),
        )?;
        need_upload = !exists.contains("YES");
        if !need_upload {
            // version check via health if agent running, else --version after start
            progress("version", "remote binary present; use --force to replace");
        }
    }

    if need_upload || force {
        progress("upload", "scp upload…");
        let mut scp = Command::new("scp");
        scp.arg("-P").arg(port.to_string());
        scp.arg("-o").arg("StrictHostKeyChecking=accept-new");
        if let Some(id) = identity {
            scp.arg("-i").arg(id);
        }
        scp.arg(&bin).arg(format!("{target}:{remote_bin}.new"));
        let st = scp.status().context("scp failed")?;
        if !st.success() {
            return Err(anyhow!("scp failed"));
        }
        ssh_exec_openssh(
            host,
            port,
            user,
            identity,
            &format!("chmod +x {remote_bin}.new && mv -f {remote_bin}.new {remote_bin}"),
        )?;
        progress("install", "installed to ~/.hm-ide-agent/bin/hm-ide-agent");
    }

    let token_arg = if token.is_empty() {
        String::new()
    } else {
        format!("--token {token}")
    };
    progress("start", &format!("starting agent on 127.0.0.1:{agent_port}…"));
    let start_cmd = format!(
        "pkill -f '[h]m-ide-agent' || true; \
         nohup {remote_bin} --port {agent_port} {token_arg} >$HOME/.hm-ide-agent/agent.log 2>&1 & \
         sleep 0.4; \
         curl -s http://127.0.0.1:{agent_port}/health || true"
    );
    let health = ssh_exec_openssh(host, port, user, identity, &start_cmd)?;
    progress("hello", &format!("health: {}", health.trim()));

    if !remote_path.is_empty() {
        progress("path", &format!("open remote path: {remote_path}"));
    }
    progress(
        "ws",
        &format!("IDE WS URL: ws://127.0.0.1:{agent_port}/ws"),
    );

    if forward {
        progress(
            "forward",
            &format!("LocalForward 127.0.0.1:{agent_port} (blocking)…"),
        );
        let mut c = Command::new("ssh");
        c.arg("-p").arg(port.to_string());
        c.arg("-o").arg("StrictHostKeyChecking=accept-new");
        c.arg("-N");
        c.arg("-L")
            .arg(format!("127.0.0.1:{agent_port}:127.0.0.1:{agent_port}"));
        if let Some(id) = identity {
            c.arg("-i").arg(id);
        }
        c.arg(&target);
        let status = c.status()?;
        if !status.success() {
            return Err(anyhow!("LocalForward ssh exited: {status}"));
        }
    }
    Ok(())
}

fn connect_ssh2(
    host: &str,
    port: u16,
    user: &str,
    identity: Option<&Path>,
    password: Option<&str>,
) -> Result<Session> {
    let tcp = TcpStream::connect(format!("{host}:{port}"))
        .with_context(|| format!("connect {host}:{port}"))?;
    let mut sess = Session::new()?;
    sess.set_tcp_stream(tcp);
    sess.handshake()?;
    if let Some(id) = identity {
        sess.userauth_pubkey_file(user, None, id, None)?;
    } else if let Some(pw) = password {
        sess.userauth_password(user, pw)?;
    } else {
        // try agent
        sess.userauth_agent(user)?;
    }
    if !sess.authenticated() {
        return Err(anyhow!("ssh2 auth failed"));
    }
    Ok(sess)
}

fn ssh2_exec(sess: &Session, cmd: &str) -> Result<String> {
    let mut channel = sess.channel_session()?;
    channel.exec(cmd)?;
    let mut s = String::new();
    channel.read_to_string(&mut s)?;
    channel.wait_close()?;
    Ok(s)
}

fn deploy_libssh2(
    host: &str,
    port: u16,
    user: &str,
    identity: Option<&Path>,
    password: Option<&str>,
    remote_path: &str,
    agent_port: u16,
    token: &str,
    binary: Option<&Path>,
    force: bool,
    forward: bool,
) -> Result<()> {
    progress("detect", "libssh2: connecting…");
    let sess = connect_ssh2(host, port, user, identity, password)?;
    let arch = ssh2_exec(&sess, "uname -m")?;
    let tag = arch_tag(arch.trim())?;
    let bin = binary
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| default_binary(tag));
    if !bin.is_file() {
        return Err(anyhow!("missing binary: {}", bin.display()));
    }
    progress("detect", &format!("arch={tag} binary={}", bin.display()));

    ssh2_exec(&sess, "mkdir -p $HOME/.hm-ide-agent/bin")?;
    let remote_bin = format!(
        "{}/.hm-ide-agent/bin/hm-ide-agent",
        ssh2_exec(&sess, "echo -n $HOME")?.trim()
    );

    let need = force
        || ssh2_exec(&sess, &format!("test -x {remote_bin} && echo YES || echo NO"))?
            .contains("NO");

    if need {
        progress("upload", "sftp upload…");
        let sftp = sess.sftp()?;
        let mut local = File::open(&bin)?;
        let remote_new = format!("{remote_bin}.new");
        let mut remote = sftp.create(Path::new(&remote_new))?;
        let mut buf = Vec::new();
        local.read_to_end(&mut buf)?;
        remote.write_all(&buf)?;
        drop(remote);
        ssh2_exec(
            &sess,
            &format!("chmod +x {remote_bin}.new && mv -f {remote_bin}.new {remote_bin}"),
        )?;
        progress("install", "installed via SFTP");
    }

    let token_arg = if token.is_empty() {
        String::new()
    } else {
        format!("--token {token}")
    };
    progress("start", "starting agent…");
    let health = ssh2_exec(
        &sess,
        &format!(
            "pkill -f '[h]m-ide-agent' || true; \
             nohup {remote_bin} --port {agent_port} {token_arg} >$HOME/.hm-ide-agent/agent.log 2>&1 & \
             sleep 0.4; curl -s http://127.0.0.1:{agent_port}/health || true"
        ),
    )?;
    progress("hello", &format!("health: {}", health.trim()));
    if !remote_path.is_empty() {
        progress("path", &format!("open remote path: {remote_path}"));
    }
    progress(
        "ws",
        &format!("IDE WS URL: ws://127.0.0.1:{agent_port}/ws"),
    );

    if forward {
        progress(
            "forward",
            &format!(
                "libssh2 deploy done. Prefer OpenSSH LocalForward: ssh -N -L 127.0.0.1:{agent_port}:127.0.0.1:{agent_port} user@host"
            ),
        );
        progress("forward", &format!("binding 127.0.0.1:{agent_port} (single-conn pump)…"));
        let listener = TcpListener::bind(format!("127.0.0.1:{agent_port}"))?;
        for stream in listener.incoming() {
            let mut client = match stream {
                Ok(s) => s,
                Err(_) => continue,
            };
            let mut channel = match sess.channel_direct_tcpip("127.0.0.1", agent_port, None) {
                Ok(c) => c,
                Err(e) => {
                    progress("forward", &format!("direct-tcpip failed: {e}"));
                    continue;
                }
            };
            let mut buf = [0u8; 8192];
            client.set_nonblocking(true).ok();
            loop {
                match client.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        if channel.write_all(&buf[..n]).is_err() {
                            break;
                        }
                        let _ = channel.flush();
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                    Err(_) => break,
                }
                match channel.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        if client.write_all(&buf[..n]).is_err() {
                            break;
                        }
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(2));
                    }
                    Err(_) => {
                        thread::sleep(Duration::from_millis(2));
                    }
                }
            }
        }
    }
    Ok(())
}

