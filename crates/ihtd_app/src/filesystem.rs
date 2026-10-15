//! Desktop document access. Reports facts and safe codes; product policy lives
//! in the shared Flutter coordinator. Never searches for a renamed destination.
use crate::storage::fingerprint;
use serde_json::{json, Value};
use std::{fs, io::Write, path::Path};
use tempfile::NamedTempFile;

pub struct Failure(pub &'static str);

fn identity(path: &Path, metadata: &fs::Metadata) -> Option<String> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        let _ = path;
        Some(format!("{}:{}", metadata.dev(), metadata.ino()))
    }
    #[cfg(windows)]
    {
        use std::os::windows::io::AsRawHandle;
        use windows_sys::Win32::Storage::FileSystem::{
            GetFileInformationByHandle, BY_HANDLE_FILE_INFORMATION,
        };
        let _ = metadata;
        let file = fs::File::open(path).ok()?;
        let mut information: BY_HANDLE_FILE_INFORMATION = unsafe { std::mem::zeroed() };
        if unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut information) } == 0 {
            return None;
        }
        Some(format!(
            "{}:{}:{}",
            information.dwVolumeSerialNumber, information.nFileIndexHigh, information.nFileIndexLow
        ))
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = (path, metadata);
        None
    }
}

fn read(path: &Path, allow_missing: bool) -> Result<Vec<u8>, Failure> {
    match fs::read(path) {
        Ok(bytes) => Ok(bytes),
        Err(e) if allow_missing && e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(_) => Err(Failure("unavailable")),
    }
}

pub fn inspect(path: &Path, allow_missing: bool) -> Result<Value, Failure> {
    let bytes = read(path, allow_missing)?;
    let metadata = match fs::metadata(path) {
        Ok(value) => Some(value),
        Err(e) if allow_missing && e.kind() == std::io::ErrorKind::NotFound => None,
        Err(_) => return Err(Failure("unavailable")),
    };
    Ok(
        json!({"name":path.file_name().map(|s| s.to_string_lossy().to_string()),
        "hash":fingerprint(&bytes), "identity":metadata.as_ref().and_then(|m| identity(path,m)),
        "size":metadata.as_ref().map(|m|m.len()),
        "modified":metadata.as_ref().and_then(|m|m.modified().ok()).and_then(|t|t.duration_since(std::time::UNIX_EPOCH).ok()).map(|t|t.as_millis() as u64),
        "writable":metadata.as_ref().map(|m|!m.permissions().readonly())}),
    )
}

fn guard(
    path: &Path,
    expected_hash: &str,
    expected_name: Option<&str>,
    expected_identity: Option<&str>,
    allow_missing: bool,
) -> Result<Value, Failure> {
    let current = inspect(path, allow_missing)?;
    if expected_name.is_some() && current["name"].as_str() != expected_name {
        return Err(Failure("renamed"));
    }
    if expected_identity.is_some() && current["identity"].as_str() != expected_identity {
        return Err(Failure("replaced"));
    }
    if current["hash"].as_str() != Some(expected_hash) {
        return Err(Failure("external_changed"));
    }
    Ok(current)
}

pub fn publish(
    path: &Path,
    working: &Path,
    expected_hash: &str,
    expected_name: Option<&str>,
    expected_identity: Option<&str>,
    allow_missing: bool,
) -> Result<Value, Failure> {
    let bytes = fs::read(working).map_err(|_| Failure("local_failed"))?;
    let current = guard(
        path,
        expected_hash,
        expected_name,
        expected_identity,
        allow_missing,
    )?;
    if current["writable"] == false {
        return Err(Failure("write_failed"));
    }
    if current["hash"].as_str() == Some(fingerprint(&bytes).as_str()) {
        return Ok(current);
    }
    let existed = fs::metadata(path).is_ok();
    // Preserve a selected symlink and publish to its existing target.
    let target = if existed {
        fs::canonicalize(path).map_err(|_| Failure("unavailable"))?
    } else {
        path.to_path_buf()
    };
    let parent = target
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut candidate = NamedTempFile::new_in(parent).map_err(|_| Failure("write_failed"))?;
    candidate
        .write_all(&bytes)
        .map_err(|_| Failure("write_failed"))?;
    if existed {
        let permissions = fs::metadata(&target)
            .map_err(|_| Failure("unavailable"))?
            .permissions();
        candidate
            .as_file()
            .set_permissions(permissions)
            .map_err(|_| Failure("write_failed"))?;
    }
    candidate
        .as_file()
        .sync_all()
        .map_err(|_| Failure("write_failed"))?;
    guard(
        path,
        expected_hash,
        expected_name,
        expected_identity,
        allow_missing,
    )?;
    if existed {
        // A changed symlink must not redirect the replacement prepared above.
        if fs::canonicalize(path).ok().as_ref() != Some(&target) {
            return Err(Failure("replaced"));
        }
        candidate
            .persist(&target)
            .map_err(|_| Failure("write_failed"))?;
    } else {
        candidate
            .persist_noclobber(&target)
            .map_err(|_| Failure("write_failed"))?;
    }
    #[cfg(unix)]
    if let Ok(directory) = fs::File::open(parent) {
        let _ = directory.sync_all();
    }
    let verified = inspect(path, false).map_err(|_| Failure("verification_failed"))?;
    if verified["hash"].as_str() != Some(fingerprint(&bytes).as_str()) {
        return Err(Failure("verification_failed"));
    }
    Ok(verified)
}

pub fn execute(request: &Value) -> Result<Value, Failure> {
    let destination = Path::new(request["destination"].as_str().unwrap_or(""));
    let allow_missing = request["allow_missing"].as_bool().unwrap_or(false);
    match request["action"].as_str() {
        Some("inspect") => inspect(destination, allow_missing),
        Some("read") => {
            let bytes = read(destination, allow_missing)?;
            Ok(json!({"hash":fingerprint(&bytes),"bytes":bytes}))
        }
        Some("hash") => {
            let bytes = fs::read(request["working"].as_str().ok_or(Failure("local_failed"))?)
                .map_err(|_| Failure("local_failed"))?;
            Ok(json!({"hash":fingerprint(&bytes)}))
        }
        Some("publish") => publish(
            destination,
            Path::new(request["working"].as_str().ok_or(Failure("local_failed"))?),
            request["expected_hash"]
                .as_str()
                .ok_or(Failure("external_changed"))?,
            request["expected_name"].as_str(),
            request["expected_identity"].as_str(),
            allow_missing,
        ),
        _ => Err(Failure("unavailable")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn guarded_atomic_write_and_replacement_detection() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("tasks.ihtd");
        let working = temp.path().join("working");
        fs::write(&path, b"old").unwrap();
        fs::write(&working, b"new").unwrap();
        let before = inspect(&path, false).ok().unwrap();
        let after = publish(
            &path,
            &working,
            before["hash"].as_str().unwrap(),
            before["name"].as_str(),
            before["identity"].as_str(),
            false,
        )
        .ok()
        .unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"new");
        assert_eq!(after["hash"], fingerprint(b"new"));
        fs::rename(&path, temp.path().join("renamed.ihtd")).unwrap();
        fs::write(&path, b"new").unwrap();
        assert!(matches!(
            publish(
                &path,
                &working,
                after["hash"].as_str().unwrap(),
                after["name"].as_str(),
                after["identity"].as_str(),
                false
            ),
            Err(Failure("replaced"))
        ));
    }
    #[test]
    fn unavailable_destination_is_not_recreated_and_conflicts_are_not_overwritten() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("tasks.ihtd");
        let working = temp.path().join("working");
        fs::write(&working, b"edited").unwrap();
        assert!(publish(&path, &working, &fingerprint(b"old"), None, None, false).is_err());
        assert!(!path.exists());
        fs::write(&path, b"external").unwrap();
        assert!(matches!(
            publish(&path, &working, &fingerprint(b"old"), None, None, false),
            Err(Failure("external_changed"))
        ));
        assert_eq!(fs::read(&path).unwrap(), b"external");
    }
    #[test]
    fn creation_and_readonly_write_failure() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("tasks.ihtd");
        let working = temp.path().join("working");
        fs::write(&working, b"edited").unwrap();
        assert!(publish(&path, &working, &fingerprint(b""), None, None, true).is_ok());
        let mut permissions = fs::metadata(&path).unwrap().permissions();
        permissions.set_readonly(true);
        fs::set_permissions(&path, permissions).unwrap();
        assert!(matches!(
            publish(&path, &working, &fingerprint(b"edited"), None, None, false),
            Err(Failure("write_failed"))
        ));
    }
}
