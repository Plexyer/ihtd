use std::sync::{Mutex, OnceLock};
use ihtd_app::Backend;

static BACKEND: OnceLock<Mutex<Backend>> = OnceLock::new();

pub fn command(request: String) -> String {
    match BACKEND.get_or_init(|| Mutex::new(Backend::default())).lock() {
        Ok(mut backend) => backend.execute(&request),
        Err(_) => r#"{"ok":false,"error":"The document worker stopped unexpectedly. Restart the app and open the preserved document."}"#.into(),
    }
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
