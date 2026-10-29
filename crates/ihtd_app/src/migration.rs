//! Pure, session-independent migration operations. Never opens a user destination
//! for writing. Shared Flutter policy verifies backups before requesting a candidate.
use crate::storage;
use rusqlite::{Connection, OpenFlags};
use serde_json::{json, Value};
use std::{fs, io::Write, path::Path};
use tempfile::NamedTempFile;

pub struct Failure(pub &'static str);

/// Read-only detection, before decoding/defaulting/recomputing model contents.
/// IHTD snapshots use rollback-journal mode and contain no live sidecars. Refuse
/// WAL snapshots: bytes alone cannot prove that committed WAL pages were included.
pub fn version(bytes: &[u8]) -> Result<u32, Failure> {
    if bytes.len() < 100 || &bytes[..16] != b"SQLite format 3\0" {
        return Err(Failure("invalid_format"));
    }
    if bytes[18] != 1 || bytes[19] != 1 {
        return Err(Failure("snapshot_required"));
    }
    let mut local = NamedTempFile::new().map_err(|_| Failure("local_failed"))?;
    local
        .write_all(bytes)
        .map_err(|_| Failure("local_failed"))?;
    let connection = Connection::open_with_flags(local.path(), OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|_| Failure("invalid_format"))?;
    let app: u32 = connection
        .query_row("PRAGMA application_id", [], |r| r.get(0))
        .map_err(|_| Failure("invalid_format"))?;
    let version: u32 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(|_| Failure("invalid_format"))?;
    let stored: String = connection
        .query_row(
            "SELECT value FROM metadata WHERE key='schema_version'",
            [],
            |r| r.get(0),
        )
        .map_err(|_| Failure("invalid_format"))?;
    if app != 0x49485444 || stored.parse::<u32>().ok() != Some(version) {
        return Err(Failure("invalid_format"));
    }
    if !(1..=ihtd_core::model::SCHEMA_VERSION).contains(&version) {
        return Err(Failure("unsupported_version"));
    }
    let check: String = connection
        .query_row("PRAGMA integrity_check", [], |r| r.get(0))
        .map_err(|_| Failure("invalid_format"))?;
    if check != "ok" {
        return Err(Failure("invalid_format"));
    }
    Ok(version)
}

pub fn require_current(bytes: &[u8]) -> Result<(), String> {
    let from = version(bytes).map_err(|e| e.0.to_string())?;
    if from != ihtd_core::model::SCHEMA_VERSION {
        return Err("Migration requires a verified backup before opening this collection.".into());
    }
    Ok(())
}

fn connection_for(bytes: &[u8]) -> Result<(NamedTempFile, Connection), Failure> {
    let mut file = NamedTempFile::new().map_err(|_| Failure("local_failed"))?;
    file.write_all(bytes).map_err(|_| Failure("local_failed"))?;
    let connection = Connection::open_with_flags(file.path(), OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|_| Failure("validation_failed"))?;
    Ok((file, connection))
}
fn retains(source: &Value, candidate: &Value) -> bool {
    match (source, candidate) {
        (Value::Object(a), Value::Object(b)) => a
            .iter()
            .all(|(key, value)| b.get(key).is_some_and(|other| retains(value, other))),
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(a, b)| retains(a, b))
        }
        _ => source == candidate,
    }
}
/// Comparing only decoded models can silently drop unknown stored fields from
/// both sides. Check the stored projection too; refuse unsupported extensions
/// rather than publish a candidate that has lost their data.
fn preserves_storage(source: &[u8], candidate: &[u8]) -> Result<(), Failure> {
    let (_source_file, before) = connection_for(source)?;
    let (_candidate_file, after) = connection_for(candidate)?;
    let invalid = |_| Failure("validation_failed");
    let mut tables = before
        .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
        .map_err(invalid)?;
    let names = tables
        .query_map([], |r| r.get::<_, String>(0))
        .map_err(invalid)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(invalid)?;
    if names
        .iter()
        .any(|name| !["metadata", "items", "tags", "views", "links"].contains(&name.as_str()))
    {
        return Err(Failure("validation_failed"));
    }
    for table in ["metadata", "items", "tags", "views", "links"] {
        let mut columns = before
            .prepare(&format!("PRAGMA table_info({table})"))
            .map_err(invalid)?;
        let columns = columns
            .query_map([], |r| r.get::<_, String>(1))
            .map_err(invalid)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(invalid)?;
        let allowed: &[&str] = match table {
            "metadata" => &["key", "value"],
            "links" => &["parent", "child", "position"],
            _ => &["id", "data"],
        };
        if columns.iter().any(|name| !allowed.contains(&name.as_str())) {
            return Err(Failure("validation_failed"));
        }
    }
    let mut meta = before
        .prepare("SELECT key,value FROM metadata WHERE key != 'schema_version'")
        .map_err(invalid)?;
    let rows = meta
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
        .map_err(invalid)?;
    for row in rows {
        let (key, value) = row.map_err(invalid)?;
        let stored: String = after
            .query_row("SELECT value FROM metadata WHERE key=?1", [key], |r| {
                r.get(0)
            })
            .map_err(invalid)?;
        // JSON metadata may be canonically serialized with different whitespace.
        if value != stored
            && !matches!((serde_json::from_str::<Value>(&value), serde_json::from_str::<Value>(&stored)), (Ok(a),Ok(b)) if a == b)
        {
            return Err(Failure("validation_failed"));
        }
    }
    for table in ["items", "tags", "views"] {
        let mut statement = before
            .prepare(&format!("SELECT id,data FROM {table}"))
            .map_err(invalid)?;
        let rows = statement
            .query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))
            .map_err(invalid)?;
        for row in rows {
            let (id, data) = row.map_err(invalid)?;
            let stored: String = after
                .query_row(
                    &format!("SELECT data FROM {table} WHERE id=?1"),
                    [id],
                    |r| r.get(0),
                )
                .map_err(invalid)?;
            let a: Value = serde_json::from_str(&data).map_err(|_| Failure("validation_failed"))?;
            let b: Value =
                serde_json::from_str(&stored).map_err(|_| Failure("validation_failed"))?;
            if !retains(&a, &b) {
                return Err(Failure("validation_failed"));
            }
        }
    }
    Ok(())
}

pub fn execute(request: &Value) -> Result<Value, Failure> {
    let source = Path::new(request["source"].as_str().ok_or(Failure("local_failed"))?);
    reject_sidecars(source)?;
    let bytes = fs::read(source).map_err(|_| Failure("local_failed"))?;
    let from = version(&bytes)?;
    let target = ihtd_core::model::SCHEMA_VERSION;
    match request["action"].as_str() {
        Some("probe") => {
            let recovery_path = if let Some(dir) = request["recovery_dir"].as_str() {
                let mut tmp = NamedTempFile::new().map_err(|_| Failure("local_failed"))?;
                tmp.write_all(&bytes).map_err(|_| Failure("local_failed"))?;
                let c = Connection::open_with_flags(tmp.path(), OpenFlags::SQLITE_OPEN_READ_ONLY)
                    .map_err(|_| Failure("invalid_format"))?;
                let id: String = c
                    .query_row(
                        "SELECT value FROM metadata WHERE key='document_id'",
                        [],
                        |r| r.get(0),
                    )
                    .map_err(|_| Failure("invalid_format"))?;
                Some(Path::new(dir).join(format!(
                    "{}-{}.ihtd",
                    storage::fingerprint(id.as_bytes()),
                    storage::fingerprint(source.to_string_lossy().as_bytes())
                )))
            } else {
                None
            };
            Ok(json!({"from":from,"target":target,"needed":from != target,
            "hash":storage::fingerprint(&bytes),"plan":"schema-1-to-2", "recovery_path":recovery_path}))
        }
        Some("prepare") => {
            if request["expected_hash"].as_str() != Some(storage::fingerprint(&bytes).as_str()) {
                return Err(Failure("source_changed"));
            }
            // Never write the source. Round-trip full model equality includes IDs,
            // all item/tag/view fields, links/order, preferences and deletion metadata.
            let before =
                storage::decode_preserving(&bytes).map_err(|_| Failure("validation_failed"))?;
            let candidate = storage::encode(&before).map_err(|_| Failure("candidate_failed"))?;
            let after =
                storage::decode_preserving(&candidate).map_err(|_| Failure("validation_failed"))?;
            preserves_storage(&bytes, &candidate)?;
            if before != after || version(&candidate)? != target {
                return Err(Failure("validation_failed"));
            }
            let destination = Path::new(
                request["candidate"]
                    .as_str()
                    .ok_or(Failure("local_failed"))?,
            );
            storage::publish(destination, &candidate, false)
                .map_err(|_| Failure("candidate_failed"))?;
            if fs::read(destination).map_err(|_| Failure("validation_failed"))? != candidate {
                return Err(Failure("validation_failed"));
            }
            Ok(
                json!({"hash":storage::fingerprint(&candidate),"validated":true,
                "items":after.items.len(),"tags":after.tags.len(),"views":after.views.len(),"links":after.links.len()}),
            )
        }
        _ => Err(Failure("invalid_operation")),
    }
}

/// Conservative: never snapshot an active SQLite store by ignoring a journal.
/// Close the other writer/checkpoint it first. IHTD itself only writes closed snapshots.
pub fn reject_sidecars(path: &Path) -> Result<(), Failure> {
    for suffix in ["-journal", "-wal", "-shm"] {
        let mut sidecar = path.as_os_str().to_os_string();
        sidecar.push(suffix);
        if Path::new(&sidecar).exists() {
            return Err(Failure("snapshot_required"));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ihtd_core::model::{Document, ItemKind};
    fn legacy(path: &Path) -> Document {
        let mut doc = Document::new("legacy-private-id".into());
        let a = doc
            .add_item(ItemKind::Folder, "Private parent".into(), None)
            .unwrap();
        let b = doc
            .add_item(ItemKind::Folder, "Other parent".into(), None)
            .unwrap();
        let t = doc
            .add_item(ItemKind::Task, "Private task".into(), Some(a))
            .unwrap();
        doc.link(b, t).unwrap();
        storage::publish(path, &storage::encode(&doc).unwrap(), false).unwrap();
        let c = Connection::open(path).unwrap();
        c.execute_batch("PRAGMA user_version=1; UPDATE metadata SET value='1' WHERE key='schema_version'; DELETE FROM metadata WHERE key='root_order';").unwrap();
        c.close().unwrap();
        doc
    }
    #[test]
    fn frozen_distributed_formats_preserve_all_fields_preferences_and_shared_links() {
        let old = include_bytes!("../../../app/test/fixtures/migration-schema1.sqlite");
        let current = include_bytes!("../../../app/test/fixtures/migration-schema2.sqlite");
        assert_eq!(version(old).ok(), Some(1));
        assert_eq!(version(current).ok(), Some(2));
        let expected = storage::decode_preserving(old).unwrap();
        assert_eq!(expected.items.len(), 4);
        assert_eq!(expected.items[&4].notes, "Synthetic notes 日本");
        assert_eq!(
            expected.views[&7].preferences[&2].hide_completed,
            Some(false)
        );
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("original");
        fs::write(&source, old).unwrap();
        let destination = dir.path().join("candidate");
        let request = json!({"action":"prepare","source":source,"candidate":destination,"expected_hash":storage::fingerprint(old)});
        assert!(execute(&request).is_ok());
        assert_eq!(
            storage::decode_preserving(&fs::read(&destination).unwrap()).unwrap(),
            expected
        );
        assert_eq!(fs::read(&source).unwrap(), old);
        // The backup can be read as the original format without converting it.
        assert_eq!(version(&fs::read(&source).unwrap()).ok(), Some(1));
    }
    #[test]
    fn detection_is_read_only_and_sessions_cannot_bypass_gate() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.ihtd");
        legacy(&source);
        let before = fs::read(&source).unwrap();
        assert_eq!(version(&before).ok(), Some(1));
        assert!(storage::Session::open(source.clone(), dir.path()).is_err());
        assert_eq!(fs::read(&source).unwrap(), before);
    }
    #[test]
    fn staged_candidate_preserves_complete_shared_model_and_source() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.ihtd");
        let expected = legacy(&source);
        let bytes = fs::read(&source).unwrap();
        let candidate = dir.path().join("candidate.ihtd");
        let result = execute(&json!({"action":"prepare","source":source,"candidate":candidate,"expected_hash":storage::fingerprint(&bytes)})).ok().unwrap();
        assert_eq!(result["validated"], true);
        assert_eq!(fs::read(&source).unwrap(), bytes);
        let migrated = fs::read(&candidate).unwrap();
        assert_eq!(version(&migrated).ok(), Some(2));
        assert_eq!(storage::decode(&migrated).unwrap(), expected);
        assert!(
            storage::Session::open_expected(candidate.clone(), dir.path(), Some("changed"))
                .is_err()
        );
        assert!(storage::Session::open_expected(
            candidate.clone(),
            dir.path(),
            Some(&storage::fingerprint(&migrated))
        )
        .is_ok());
        let mut session = storage::Session::open(candidate.clone(), dir.path()).unwrap();
        session.restore_recovery_if_newer(&candidate).unwrap();
        assert!(
            !session.dirty,
            "an equal-revision recovery is not a failed private save"
        );
        assert!(execute(&json!({"action":"prepare","source":source,"candidate":candidate,"expected_hash":storage::fingerprint(&bytes)})).is_err());
    }
    #[test]
    fn unknown_fields_are_not_silently_lost_by_model_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source");
        fs::write(
            &source,
            include_bytes!("../../../app/test/fixtures/migration-schema1.sqlite"),
        )
        .unwrap();
        let c = Connection::open(&source).unwrap();
        c.execute_batch(
            "UPDATE items SET data=json_set(data,'$.future_field','must survive') WHERE id=4;",
        )
        .unwrap();
        c.close().unwrap();
        let bytes = fs::read(&source).unwrap();
        let candidate = dir.path().join("candidate");
        assert!(matches!(
            execute(
                &json!({"action":"prepare","source":source,"candidate":candidate,"expected_hash":storage::fingerprint(&bytes)})
            ),
            Err(Failure("validation_failed"))
        ));
        assert!(!candidate.exists());
        assert_eq!(fs::read(&source).unwrap(), bytes);
    }

    #[test]
    fn conflicts_journals_wal_and_corruption_never_create_candidates() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.ihtd");
        legacy(&source);
        let candidate = dir.path().join("candidate.ihtd");
        assert!(execute(&json!({"action":"prepare","source":source,"candidate":candidate,"expected_hash":"stale"})).is_err());
        assert!(!candidate.exists());
        fs::write(source.with_extension("ihtd-wal"), b"pending").unwrap();
        assert!(matches!(
            execute(&json!({"action":"probe","source":source})),
            Err(Failure("snapshot_required"))
        ));
        let mut bytes = fs::read(&source).unwrap();
        bytes[18] = 2;
        assert!(matches!(version(&bytes), Err(Failure("snapshot_required"))));
        bytes[18] = 1;
        bytes[68] = 0;
        assert!(version(&bytes).is_err());
    }
}
