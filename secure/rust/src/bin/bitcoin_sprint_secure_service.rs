//! SecureBuffer service (Windows service + cross‑platform daemon)
//! Hardened version: removes insecure HTTP secret exposure, fixes quotes,
//! adds stop handling, avoids returning plaintext secrets, and adds basic
//! auditing/log redaction. Feature flags:
//! - api (optional): enable a loopback token‑auth API **without** returning secrets.
//! - system-tray (optional): basic tray app wrapper.

// If your crate is named `secure_buffer`, use this:
use secure_buffer::{SecureBuffer, SecureString};
// If it's actually `securebuffer` in Cargo.toml, then keep `use securebuffer::...`
use std::collections::HashMap;
use std::ffi::OsString;
use std::sync::{Arc, Mutex, atomic::{AtomicBool, Ordering}};
use std::time::Duration;

use lazy_static::lazy_static;

lazy_static! {
    static ref SECURE_VAULT: Arc<Mutex<SecureVault>> = Arc::new(Mutex::new(SecureVault::new()));
    static ref RUNNING: AtomicBool = AtomicBool::new(true);
}

// ---------------------- Secure vault ----------------------
#[derive(Default)]
struct SecureVault {
    passwords: HashMap<String, SecureString>,
    api_keys: HashMap<String, SecureString>,
    certificates: HashMap<String, SecureBuffer>,
}

impl SecureVault {
    fn new() -> Self { Self::default() }

    fn store_password(&mut self, key: &str, password: &str) -> anyhow::Result<()> {
        let secure_password = SecureString::new(password)?;
        self.passwords.insert(key.to_owned(), secure_password);
        log_redacted("password", key);
        Ok(())
    }

    /// Do **not** return a new String (copies secret). Instead, expose via closure.
    fn with_password<R>(&self, key: &str, f: impl FnOnce(&str) -> R) -> Option<R> {
        self.passwords.get(key).and_then(|sp| sp.with_str(|s| Some(f(s))).ok())
    }

    fn store_api_key(&mut self, service: &str, key: &str) -> anyhow::Result<()> {
        let secure_key = SecureString::new(key)?;
        self.api_keys.insert(service.to_owned(), secure_key);
        log_redacted("api_key", service);
        Ok(())
    }

    fn store_certificate(&mut self, name: &str, cert_data: &[u8]) -> anyhow::Result<()> {
        let mut secure_cert = SecureBuffer::new(cert_data.len())?;
        secure_cert.with_buffer(|buf| buf.copy_from_slice(cert_data))?;
        self.certificates.insert(name.to_owned(), secure_cert);
        log_redacted("certificate", name);
        Ok(())
    }
}

fn log_redacted(kind: &str, label: &str) {
    // Avoid logging full labels if they can be sensitive; hash a short fingerprint.
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    label.hash(&mut h);
    let fp = h.finish();
    println!("[SERVICE] Stored {kind} for id=0x{fp:08x}");
}

// ---------------------- Entry points ----------------------
#[cfg(windows)]
fn main() -> Result<(), windows_service::Error> {
    use windows_service::service_dispatcher;
    service_dispatcher::start("SecureBufferService", ffi_service_main)
}

#[cfg(windows)]
windows_service::define_windows_service!(ffi_service_main, secure_buffer_service_main);

#[cfg(windows)]
fn secure_buffer_service_main(_arguments: Vec<OsString>) {
    if let Err(e) = run_service() {
        eprintln!("Service error: {e}");
    }
}

#[cfg(windows)]
fn run_service() -> anyhow::Result<()> {
    use windows_service::service::{ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus, ServiceType};
    use windows_service::service_control_handler::{self, ServiceControlHandlerResult};

    let status_handle = service_control_handler::register("SecureBufferService", move |control| match control {
        ServiceControl::Stop | ServiceControl::Shutdown => { RUNNING.store(false, Ordering::SeqCst); ServiceControlHandlerResult::NoError }
        ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
        _ => ServiceControlHandlerResult::NotImplemented,
    })?;

    // StartPending → Running
    status_handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: ServiceState::StartPending,
        controls_accepted: ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 1,
        wait_hint: Duration::from_secs(2),
        process_id: None,
    })?;

    initialize_secure_vault()?;

    status_handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    println!("[SERVICE] SecureBuffer Service started");

    // Main loop
    while RUNNING.load(Ordering::SeqCst) {
        std::thread::sleep(Duration::from_secs(10));
        perform_security_check();
        perform_memory_check();
    }

    // StopPending → Stopped
    status_handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: ServiceState::StopPending,
        controls_accepted: ServiceControlAccept::empty(),
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 1,
        wait_hint: Duration::from_secs(2),
        process_id: None,
    })?;

    status_handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: ServiceState::Stopped,
        controls_accepted: ServiceControlAccept::empty(),
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    Ok(())
}

// ---------------------- Cross‑platform daemon ----------------------
#[cfg(not(windows))]
fn main() -> anyhow::Result<()> {
    println!("Starting SecureBuffer Background Service...");
    setup_signal_handlers();
    initialize_secure_vault()?;

    #[cfg(feature = "api")]
    start_api_server()?; // token‑auth status API (no secret retrieval)

    run_background_service()
}

fn setup_signal_handlers() {
    #[cfg(unix)]
    {
        use signal_hook::{consts::{SIGTERM, SIGINT}, iterator::Signals};
        let r = &*RUNNING as *const AtomicBool as usize; // avoid move
        std::thread::spawn(move || {
            let mut signals = Signals::new(&[SIGTERM, SIGINT]).unwrap();
            for _sig in signals.forever() {
                println!("[SERVICE] Received shutdown signal");
                unsafe { (*(r as *const AtomicBool)).store(false, Ordering::SeqCst); }
                break;
            }
        });
    }
}

fn initialize_secure_vault() -> anyhow::Result<()> {
    let mut vault = SECURE_VAULT.lock().unwrap();

    // Load from env if present (never hardcode secrets).
    if let Ok(db_password) = std::env::var("DATABASE_PASSWORD") {
        vault.store_password("database", &db_password)?;
        // db_password memory remains in env; prefer passing via secure buffer in prod
    }
    if let Ok(stripe_key) = std::env::var("STRIPE_SECRET_KEY") {
        vault.store_api_key("stripe", &stripe_key)?;
    }
    if let Ok(jwt_secret) = std::env::var("JWT_SECRET") {
        vault.store_password("jwt_secret", &jwt_secret)?;
    }

    // Optional: load certificate bytes from file path via env
    if let Ok(cert_path) = std::env::var("SECUREBUFFER_CERT_PATH") {
        let data = std::fs::read(cert_path)?;
        vault.store_certificate("web_server", &data)?;
    }

    Ok(())
}

#[cfg(feature = "api")]
fn start_api_server() -> anyhow::Result<()> {
    use std::net::TcpListener;
    use std::thread;

    // Loopback only; token required via X-API-Key.
    let listener = TcpListener::bind("127.0.0.1:8081")?;
    println!("[SERVICE] Status API listening on 127.0.0.1:8081");
    thread::spawn(move || {
        for stream in listener.incoming() {
            match stream {
                Ok(s) => { thread::spawn(|| { let _ = handle_client(s); }); }
                Err(e) => eprintln!("[SERVICE] Connection error: {e}"),
            }
        }
    });
    Ok(())
}

#[cfg(feature = "api")]
fn handle_client(mut stream: std::net::TcpStream) -> anyhow::Result<()> {
    use std::io::{Read, Write};
    let mut buf = [0u8; 2048];
    let n = stream.read(&mut buf)?;
    let req = String::from_utf8_lossy(&buf[..n]);

    // Very small parser: require GET /status and correct header
    let expected = std::env::var("SECUREBUFFER_TOKEN").unwrap_or_default();
    let header = req.lines()
        .find(|l| l.to_ascii_lowercase().starts_with("x-api-key:"))
        .map(|l| l.splitn(2, ':').nth(1).unwrap_or("").trim());
    let authorized = header.map(|h| h == expected).unwrap_or(false);

    if !authorized {
        stream.write_all(b"HTTP/1.1 401 Unauthorized\r\n\r\n")?; return Ok(());
    }

    if let Some(line) = req.lines().next() {
        if line.starts_with("GET /status") {
            let v = SECURE_VAULT.lock().unwrap();
            let body = format!("{{\"passwords\":{},\"api_keys\":{},\"certs\":{}}}\n", v.passwords.len(), v.api_keys.len(), v.certificates.len());
            write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{}", body)?;
            return Ok(());
        }
    }
    stream.write_all(b"HTTP/1.1 404 Not Found\r\n\r\n")?;
    Ok(())
}

fn run_background_service() -> anyhow::Result<()> {
    println!("[SERVICE] Background service running...");
    while RUNNING.load(Ordering::SeqCst) {
        std::thread::sleep(Duration::from_secs(30));
        perform_security_check();
        perform_memory_check();
        println!("[SERVICE] Heartbeat — secure buffers active");
    }
    Ok(())
}

fn perform_security_check() {
    if SecureBuffer::detect_debugger() {
        println!("[SECURITY] WARNING: Debugger detected!");
        // Consider: lock sensitive data, alert, or exit.
    }
    let v = SECURE_VAULT.lock().unwrap();
    println!("[SECURITY] Protecting {} passwords, {} API keys, {} certificates", v.passwords.len(), v.api_keys.len(), v.certificates.len());
}

fn perform_memory_check() {
    #[cfg(unix)]
    {
        if let Ok(status) = std::fs::read_to_string("/proc/self/status") {
            if let Some(l) = status.lines().find(|l| l.starts_with("VmLck:")) { println!("[MEMORY] {l}"); }
        }
    }
}

// ---------------------- Optional: installers ----------------------
#[cfg(windows)]
pub fn install_windows_service() -> anyhow::Result<()> {
    use std::process::Command;
    let exe = std::env::current_exe()?;
    let exe_quoted = format!("\"{}\"", exe.display());
    // sc.exe expects space after binPath= and quoted path if it contains spaces
    let out = Command::new("sc").args([
        "create", "SecureBufferService",
        &format!("binPath= {}", exe_quoted),
        "DisplayName= SecureBuffer Service",
        "start= auto",
    ]).output()?;
    if !out.status.success() { anyhow::bail!("sc create failed: {}", String::from_utf8_lossy(&out.stderr)); }
    println!("Service installed. Run: net start SecureBufferService");
    Ok(())
}

#[cfg(unix)]
pub fn install_systemd_service() -> anyhow::Result<()> {
    use std::fs;
    let exe = std::env::current_exe()?;
    let unit = format!("[Unit]\nDescription=SecureBuffer Service\nAfter=network.target\n\n[Service]\nType=simple\nUser=secure-buffer\nExecStart={}\nRestart=always\nRestartSec=5\nNoNewPrivileges=true\nPrivateTmp=true\nProtectSystem=full\nProtectHome=true\n\n[Install]\nWantedBy=multi-user.target\n", exe.display());
    fs::write("/etc/systemd/system/secure-buffer.service", unit)?;
    println!("Wrote unit. Run: sudo systemctl daemon-reload && sudo systemctl enable --now secure-buffer");
    Ok(())
}

// ---------------------- Examples ----------------------
#[allow(dead_code)]
fn example_usage() -> anyhow::Result<()> {
    println!("=== SecureBuffer Service Examples ===");
    {
        let mut v = SECURE_VAULT.lock().unwrap();
        v.store_password("user123", "my_super_secret_password")?;
        let _ = v.with_password("user123", |pw| {
            let _len = pw.len(); // use without cloning
        });
    }
    {
        let mut v = SECURE_VAULT.lock().unwrap();
        v.store_api_key("payment_processor", "sk_live_abcdef123456")?;
    }
    {
        let mut v = SECURE_VAULT.lock().unwrap();
        let cert_data = b"-----BEGIN CERTIFICATE-----\nMIIC...";
        v.store_certificate("ssl_cert", cert_data)?;
    }
    Ok(())
}
