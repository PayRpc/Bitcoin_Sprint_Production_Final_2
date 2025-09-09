//! Cross-platform SecureBuffer service
//!
//! - Uses `once_cell::sync::Lazy` for a global vault
//! - Supports Windows service wiring behind `cfg(windows)`
//! - Supports Unix graceful shutdown via signal hooks
//! - Provides a tiny TCP API on 127.0.0.1:8080 for demo/testing

use once_cell::sync::Lazy;
use securebuffer::SecureBuffer;
use std::net::TcpStream;
use std::collections::HashMap;
use std::ffi::OsString;
use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use axum::{routing::get, Json, Router, extract::Path, http::StatusCode};
use axum::http::HeaderMap;
use axum::serve;
use tower_http::trace::TraceLayer;
use serde::Serialize;
// Note: middleware removed for simplicity in this focused demo; the
// get-password handler performs API-key validation inline to avoid
// type-bound complexities with axum middleware layers in this repo.

// Temporary in-memory vault types (replace with secure secret types later)
type InnerVault = HashMap<String, String>;

pub struct SecureVault {
    passwords: InnerVault,
    api_keys: InnerVault,
    certificates: HashMap<String, SecureBuffer>,
}

impl SecureVault {
    pub fn new() -> Self {
        SecureVault {
            passwords: HashMap::new(),
            api_keys: HashMap::new(),
            certificates: HashMap::new(),
        }
    }

    pub fn store_password(&mut self, name: &str, pw: &str) -> Result<(), Box<dyn std::error::Error>> {
        // TODO: replace with SecureString when available
        self.passwords.insert(name.to_string(), pw.to_string());
        log::info!("Stored password for {}", name);
        Ok(())
    }

    pub fn get_password(&self, key: &str) -> Option<String> {
        self.passwords.get(key).cloned()
    }

    pub fn store_api_key(&mut self, service: &str, key: &str) -> Result<(), Box<dyn std::error::Error>> {
        // TODO: replace with SecureString when available
        self.api_keys.insert(service.to_string(), key.to_string());
        log::info!("Stored API key for {}", service);
        Ok(())
    }

    pub fn store_certificate(&mut self, name: &str, cert_data: &[u8]) -> Result<(), Box<dyn std::error::Error>> {
        let mut buf = SecureBuffer::new(cert_data.len()).map_err(|s| Box::<dyn std::error::Error>::from(s))?;
        // SecureBuffer currently exposes `write` and `read` APIs in the crate; use `write` to populate.
        buf.write(cert_data).map_err(|s| Box::<dyn std::error::Error>::from(s))?;
        self.certificates.insert(name.to_string(), buf);
        log::info!("Stored certificate {}", name);
        Ok(())
    }
}

/// Global vault instance for the service. Use `.lock()` to access.
pub static SECURE_VAULT: Lazy<Arc<Mutex<SecureVault>>> = Lazy::new(|| Arc::new(Mutex::new(SecureVault::new())));

// ------------------ Common runtime ------------------

fn initialize_from_env() {
    let mut vault = SECURE_VAULT.lock().unwrap();

    if let Ok(db_password) = std::env::var("DATABASE_PASSWORD") {
        let _ = vault.store_password("database", &db_password);
    }
    if let Ok(stripe_key) = std::env::var("STRIPE_SECRET_KEY") {
        let _ = vault.store_api_key("stripe", &stripe_key);
    }
    if let Ok(jwt_secret) = std::env::var("JWT_SECRET") {
        let _ = vault.store_password("jwt_secret", &jwt_secret);
    }
}

fn perform_security_check() {
    let vault = SECURE_VAULT.lock().unwrap();
    let password_count = vault.passwords.len();
    let key_count = vault.api_keys.len();
    let cert_count = vault.certificates.len();

    log::info!("Protecting {} passwords, {} API keys, {} certificates", password_count, key_count, cert_count);
}

/// Middleware: require X-API-Key header and validate against stored API keys in the vault.
// api_key_middleware removed; handler-level validation used instead.

// Minimal HTTP-like handler for demo purposes. Do not expose in production.
fn handle_client(mut stream: TcpStream) {
    let mut buffer = [0u8; 1024];
    match stream.read(&mut buffer) {
        Ok(size) if size > 0 => {
            let request = String::from_utf8_lossy(&buffer[..size]);
            if request.starts_with("GET /password/") {
                // parse a very small subset of HTTP
                if let Some(line) = request.lines().next() {
                    let path = line.trim();
                    if let Some(remainder) = path.strip_prefix("GET /password/") {
                        let key = remainder.trim_end_matches(" HTTP/1.1").trim();
                        let vault = SECURE_VAULT.lock().unwrap();
                        if let Some(pw) = vault.get_password(key) {
                            let response = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}", pw.len(), pw);
                            let _ = stream.write_all(response.as_bytes());
                            log::info!("Served password for {}", key);
                            return;
                        }
                        let resp = "HTTP/1.1 404 NOT FOUND\r\nContent-Length: 14\r\n\r\nPassword not found";
                        let _ = stream.write_all(resp.as_bytes());
                        return;
                    }
                }
            }
            // default
            let resp = "HTTP/1.1 400 BAD REQUEST\r\nContent-Length: 11\r\n\r\nBad request";
            let _ = stream.write_all(resp.as_bytes());
        }
        _ => {}
    }
}

#[derive(Serialize)]
struct PasswordResponse {
    password: String,
}

use axum::extract::Query;
use std::collections::BTreeMap;

async fn get_password_handler(
    headers: HeaderMap,
    Path(key): Path<String>,
    Query(q): Query<BTreeMap<String, String>>,
) -> Result<Json<PasswordResponse>, (axum::http::StatusCode, String)> {
    // server-side validation: key length and characters
    if key.len() == 0 || key.len() > 128 {
        return Err((StatusCode::BAD_REQUEST, "Invalid key".to_string()));
    }
    if !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return Err((StatusCode::BAD_REQUEST, "Invalid key characters".to_string()));
    }

    let reveal = q.get("reveal").map(|v| v == "true").unwrap_or(false);

    // Validate API key header inline (demo only). In production use a
    // middleware with constant-time comparisons and avoid extracting
    // secrets into plain memory.
    let key_header = headers.get("x-api-key").and_then(|v| v.to_str().ok()).map(|s| s.to_string());
    if key_header.is_none() {
        return Err((StatusCode::UNAUTHORIZED, "Missing X-API-Key header".to_string()));
    }
    let api_key = key_header.unwrap();

    let vault = SECURE_VAULT.lock().unwrap();
    let mut authorized = false;
    for (_svc, stored) in vault.api_keys.iter() {
        if stored == &api_key {
            authorized = true;
            break;
        }
    }
    if !authorized {
        return Err((StatusCode::FORBIDDEN, "Invalid API key".to_string()));
    }
    if let Some(pw) = vault.get_password(&key) {
        if reveal {
            // explicit reveal requested and authorized by middleware
            Ok(Json(PasswordResponse { password: pw }))
        } else {
            // return redacted placeholder
            Ok(Json(PasswordResponse { password: "REDACTED".to_string() }))
        }
    } else {
        Err((axum::http::StatusCode::NOT_FOUND, "Password not found".to_string()))
    }
}

async fn start_api_server() -> Result<(), Box<dyn std::error::Error>> {
    log::info!("Starting API server setup...");

    let app = Router::new()
        .route("/password/:key", get(get_password_handler))
        .route("/healthz", get(|| async {
            log::info!("Health check requested");
            (StatusCode::OK, "ok")
        }))
        // global tracing
        .layer(TraceLayer::new_for_http());

    let addr = std::net::SocketAddr::from(([127, 0, 0, 1], 8082));
    log::info!("Attempting to bind to address: {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    log::info!("Successfully bound to address: {}", addr);
    log::info!("HTTP API server listening on {}", addr);

    serve(listener, app).await.map_err(|e| -> Box<dyn std::error::Error> { Box::new(e) })?;

    Ok(())
}

// ------------------ Platform: Unix / background ------------------

#[cfg(not(windows))]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();
    log::info!("Starting SecureBuffer background service (unix)");

    // Setup signal handlers for graceful termination
    let running = setup_signal_handlers();

    // Initialize vault from env
    initialize_from_env();

    // Optionally preload demo data (safe for local dev only)
    {
        let mut vault = SECURE_VAULT.lock().unwrap();
        let _ = vault.store_password("database", "");
    }

    // Start the async runtime and HTTP server
    let rt = tokio::runtime::Runtime::new()?;
    let handle = rt.handle().clone();

    // spawn server on runtime
    handle.spawn(async move {
        if let Err(e) = start_api_server().await {
            log::error!("API server error: {}", e);
        }
    });

    // periodic checks until shutdown requested
    while running.load(std::sync::atomic::Ordering::SeqCst) {
        std::thread::sleep(Duration::from_secs(30));
        perform_security_check();
    }

    log::info!("Shutdown requested, stopping runtime");
    // Dropping the runtime will try to stop spawned tasks; in complex cases use a shutdown channel
    drop(rt);
    Ok(())
}

#[cfg(not(windows))]
fn setup_signal_handlers() -> Arc<std::sync::atomic::AtomicBool> {
    use signal_hook::{consts::SIGTERM, iterator::Signals};
    use std::sync::atomic::{AtomicBool, Ordering};

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();
    std::thread::spawn(move || {
        let mut signals = Signals::new(&[SIGTERM]).expect("failed to create signals");
        for _sig in signals.forever() {
            log::info!("Received shutdown signal");
            r.store(false, Ordering::SeqCst);
            break;
        }
    });
    running
}

// ------------------ Platform: Windows service ------------------

#[cfg(windows)]
use windows_service::{
    define_windows_service,
    service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus, ServiceType,
    },
    service_control_handler::{self, ServiceControlHandlerResult},
    service_dispatcher,
};

#[cfg(windows)]
define_windows_service!(ffi_service_main, secure_buffer_service_main);

#[cfg(windows)]
fn main() -> Result<(), windows_service::Error> {
    // Check if we're being run as a service or standalone
    let args: Vec<String> = std::env::args().collect();

    if args.len() > 1 {
        // Run as service dispatcher
        service_dispatcher::start("SecureBufferService", ffi_service_main)
    } else {
        // Run standalone
        run_standalone()
    }
}

#[cfg(windows)]
fn run_standalone() -> Result<(), windows_service::Error> {
    env_logger::init();
    log::info!("Starting SecureBuffer service (windows standalone mode)");

    // Initialize vault from env
    log::info!("Initializing vault from environment variables...");
    initialize_from_env();
    log::info!("Vault initialization complete");

    // Optionally preload demo data (safe for local dev only)
    {
        let mut vault = SECURE_VAULT.lock().unwrap();
        let _ = vault.store_password("database", "");
        let _ = vault.store_api_key("bitcoin_sprint", "YmuWANtGBbzJg60CqVSrlxjsF84Xno5fKyPpO3E9DawTL2cI7Mkd1RhQeHZviU");
        log::info!("Preloaded demo data");
    }

    // Start async runtime and HTTP server
    log::info!("Creating Tokio runtime...");
    let rt = tokio::runtime::Runtime::new().expect("Failed to create runtime");
    log::info!("Tokio runtime created successfully");

    rt.block_on(async {
        let handle = rt.handle().clone();
        log::info!("Spawning API server task...");

        // Spawn server on runtime
        handle.spawn(async move {
            if let Err(e) = start_api_server().await {
                log::error!("API server error: {}", e);
            }
        });

        log::info!("API server task spawned, waiting for Ctrl+C...");

        // Wait for Ctrl+C or other termination
        match tokio::signal::ctrl_c().await {
            Ok(()) => {
                log::info!("Received Ctrl+C, shutting down");
            }
            Err(err) => {
                log::error!("Unable to listen for shutdown signal: {}", err);
            }
        }
    });

    log::info!("Shutting down runtime");
    Ok(())
}

#[cfg(windows)]
fn secure_buffer_service_main(_arguments: Vec<OsString>) {
    if let Err(e) = run_service() {
        eprintln!("Service error: {}", e);
    }
}

#[cfg(windows)]
fn run_service() -> Result<(), Box<dyn std::error::Error>> {
    let event_handler = move |control_event| -> ServiceControlHandlerResult {
        match control_event {
            ServiceControl::Stop => {
                log::info!("Received stop");
                ServiceControlHandlerResult::NoError
            }
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            _ => ServiceControlHandlerResult::NotImplemented,
        }
    };

    let status_handle = service_control_handler::register("SecureBufferService", event_handler)?;

    status_handle.set_service_status(ServiceStatus {
        service_type: ServiceType::OWN_PROCESS,
        current_state: ServiceState::Running,
        controls_accepted: ServiceControlAccept::STOP,
        exit_code: ServiceExitCode::Win32(0),
        checkpoint: 0,
        wait_hint: Duration::default(),
        process_id: None,
    })?;

    env_logger::init();
    log::info!("SecureBuffer service started (windows)");

    // Initialize vault
    initialize_from_env();

    // Start async runtime and HTTP server
    let rt = tokio::runtime::Runtime::new()?;
    rt.spawn(async move {
        if let Err(e) = start_api_server().await {
            log::error!("API server error: {}", e);
        }
    });

    // Simple loop - in production you'd watch for stop signals and exit cleanly
    loop {
        std::thread::sleep(Duration::from_secs(10));
        perform_security_check();
    }
}

// ------------------ Optional: system-tray feature ------------------
#[cfg(feature = "system-tray")]
pub fn run_system_tray_app() -> Result<(), Box<dyn std::error::Error>> {
    log::info!("Starting system tray app (not implemented in this demo)");
    Ok(())
}
