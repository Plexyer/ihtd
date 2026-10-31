//! Closed SQLite document snapshots. No SQLite connection touches a mounted path.
use ihtd_core::model::{Document, Item, Link, Tag, View};
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    io::Write,
    path::{Path, PathBuf},
};
use tempfile::NamedTempFile;

const APPLICATION_ID: i64 = 0x49485444;

#[cfg(test)]
mod migration_tests {
    use super::*;
    use ihtd_core::model::ItemKind;
    #[test]
    fn version_one_documents_migrate_and_shared_roots_roundtrip() {
        let mut doc = Document::new("legacy".into());
        let a = doc.add_item(ItemKind::Folder, "A".into(), None).unwrap();
        let b = doc.add_item(ItemKind::Folder, "B".into(), None).unwrap();
        let task = doc
            .add_item(ItemKind::Task, "Task".into(), Some(a))
            .unwrap();
        doc.link(b, task).unwrap();
        let file = NamedTempFile::new().unwrap();
        fs::write(file.path(), encode(&doc).unwrap()).unwrap();
        let connection = Connection::open(file.path()).unwrap();
        connection.execute_batch("PRAGMA user_version=1; UPDATE metadata SET value='1' WHERE key='schema_version'; DELETE FROM metadata WHERE key IN ('root_order','deleted_item_ids');").unwrap();
        connection.close().unwrap();
        let mut migrated = decode(&fs::read(file.path()).unwrap()).unwrap();
        assert_eq!(migrated, doc);
        migrated.move_item(task, Some(a), None, Some(b)).unwrap();
        let reopened = decode(&encode(&migrated).unwrap()).unwrap();
        assert_eq!(reopened, migrated);
        assert!(reopened.roots().contains(&task));
        assert!(reopened
            .links
            .iter()
            .any(|l| l.parent == b && l.child == task));
    }
}
pub fn fingerprint(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

pub fn encode(document: &Document) -> Result<Vec<u8>, String> {
    document.validate()?;
    let tmp = NamedTempFile::new().map_err(err)?;
    let mut connection = Connection::open(tmp.path()).map_err(err)?;
    connection.execute_batch(&format!(
        "PRAGMA application_id={APPLICATION_ID}; PRAGMA user_version=2;
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE items (id INTEGER PRIMARY KEY, data TEXT NOT NULL);
        CREATE TABLE tags (id INTEGER PRIMARY KEY, data TEXT NOT NULL);
        CREATE TABLE views (id INTEGER PRIMARY KEY, data TEXT NOT NULL);
        CREATE TABLE links (parent INTEGER NOT NULL, child INTEGER NOT NULL, position INTEGER NOT NULL, PRIMARY KEY(parent, child));"
    )).map_err(err)?;
    let transaction = connection.transaction().map_err(err)?;
    for (key, value) in [
        ("document_id", document.document_id.clone()),
        (
            "deleted_item_ids",
            serde_json::to_string(&document.deleted_item_ids).map_err(err)?,
        ),
        ("revision", document.revision.to_string()),
        ("next_id", document.next_id.to_string()),
        ("schema_version", document.schema_version.to_string()),
        (
            "root_order",
            serde_json::to_string(&document.root_order).map_err(err)?,
        ),
    ] {
        transaction
            .execute("INSERT INTO metadata VALUES (?1,?2)", params![key, value])
            .map_err(err)?;
    }
    for (key, value) in [
        (
            "collection_settings",
            serde_json::to_string(&document.collection_settings).map_err(err)?,
        ),
        (
            "parent_indicator_defaults",
            serde_json::to_string(&document.parent_indicator_defaults).map_err(err)?,
        ),
    ] {
        transaction
            .execute("INSERT INTO metadata VALUES (?1,?2)", params![key, value])
            .map_err(err)?;
    }
    if !document.tag_usage.is_empty() {
        transaction
            .execute(
                "INSERT INTO metadata VALUES (?1,?2)",
                params![
                    "tag_usage",
                    serde_json::to_string(&document.tag_usage).map_err(err)?
                ],
            )
            .map_err(err)?;
    }
    for item in document.items.values() {
        transaction
            .execute(
                "INSERT INTO items VALUES (?1,?2)",
                params![item.id, serde_json::to_string(item).map_err(err)?],
            )
            .map_err(err)?;
    }
    for tag in document.tags.values() {
        transaction
            .execute(
                "INSERT INTO tags VALUES (?1,?2)",
                params![tag.id, serde_json::to_string(tag).map_err(err)?],
            )
            .map_err(err)?;
    }
    for view in document.views.values() {
        transaction
            .execute(
                "INSERT INTO views VALUES (?1,?2)",
                params![view.id, serde_json::to_string(view).map_err(err)?],
            )
            .map_err(err)?;
    }
    for (position, link) in document.links.iter().enumerate() {
        transaction
            .execute(
                "INSERT INTO links VALUES (?1,?2,?3)",
                params![link.parent, link.child, position as i64],
            )
            .map_err(err)?;
    }
    transaction.commit().map_err(err)?;
    connection.close().map_err(|(_, error)| err(error))?;
    fs::read(tmp.path()).map_err(err)
}

pub fn decode(bytes: &[u8]) -> Result<Document, String> {
    let mut document = decode_preserving(bytes)?;
    document.recompute_completion()?;
    Ok(document)
}

/// Migration validation must preserve stored field values, not compare two
/// independently normalized versions that could both hide the same data loss.
pub fn decode_preserving(bytes: &[u8]) -> Result<Document, String> {
    let mut local = NamedTempFile::new().map_err(err)?;
    local.write_all(bytes).map_err(err)?;
    local.flush().map_err(err)?;
    let connection =
        Connection::open_with_flags(local.path(), rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .map_err(err)?;
    let app_id: i64 = connection
        .query_row("PRAGMA application_id", [], |r| r.get(0))
        .map_err(err)?;
    let version: i64 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(err)?;
    if app_id != APPLICATION_ID || !(1..=2).contains(&version) {
        return Err("This is not a supported IHTD document".into());
    }
    let check: String = connection
        .query_row("PRAGMA quick_check", [], |r| r.get(0))
        .map_err(err)?;
    if check != "ok" {
        return Err(format!("Document integrity check failed: {check}"));
    }
    let metadata = |key: &str| -> Result<String, String> {
        connection
            .query_row("SELECT value FROM metadata WHERE key=?1", [key], |r| {
                r.get(0)
            })
            .map_err(err)
    };
    let read_map = |table: &str| -> Result<Vec<(i64, String)>, String> {
        // Table names are constants chosen here, never input from a file or filter.
        let mut statement = connection
            .prepare(&format!("SELECT id,data FROM {table} ORDER BY id"))
            .map_err(err)?;
        let result = statement
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(err)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(err)?;
        Ok(result)
    };
    let stored_schema: u32 = metadata("schema_version")?.parse().map_err(err)?;
    if i64::from(stored_schema) != version {
        return Err("Inconsistent document schema".into());
    }
    let root_order: Option<String> = connection
        .query_row(
            "SELECT value FROM metadata WHERE key='root_order'",
            [],
            |r| r.get(0),
        )
        .optional()
        .map_err(err)?;
    let deleted_item_ids: Option<String> = connection
        .query_row(
            "SELECT value FROM metadata WHERE key='deleted_item_ids'",
            [],
            |r| r.get(0),
        )
        .optional()
        .map_err(err)?;
    let optional_json = |key: &str| -> Result<Option<String>, String> {
        connection
            .query_row("SELECT value FROM metadata WHERE key=?1", [key], |r| {
                r.get(0)
            })
            .optional()
            .map_err(err)
    };
    let mut document = Document {
        tag_usage: optional_json("tag_usage")?
            .map(|s| serde_json::from_str(&s).map_err(err))
            .transpose()?
            .unwrap_or_default(),
        schema_version: ihtd_core::model::SCHEMA_VERSION,
        collection_settings: optional_json("collection_settings")?
            .map(|s| serde_json::from_str(&s).map_err(err))
            .transpose()?
            .unwrap_or_default(),
        parent_indicator_defaults: optional_json("parent_indicator_defaults")?
            .map(|s| serde_json::from_str(&s).map_err(err))
            .transpose()?
            .unwrap_or_default(),
        document_id: metadata("document_id")?,
        revision: metadata("revision")?.parse().map_err(err)?,
        next_id: metadata("next_id")?.parse().map_err(err)?,
        items: BTreeMap::new(),
        tags: BTreeMap::new(),
        views: BTreeMap::new(),
        links: Vec::new(),
        deleted_item_ids: deleted_item_ids
            .map(|s| serde_json::from_str(&s).map_err(err))
            .transpose()?
            .unwrap_or_default(),
        root_order: root_order
            .map(|s| serde_json::from_str(&s).map_err(err))
            .transpose()?
            .unwrap_or_default(),
    };
    for (id, data) in read_map("items")? {
        document
            .items
            .insert(id, serde_json::from_str::<Item>(&data).map_err(err)?);
    }
    for (id, data) in read_map("tags")? {
        document
            .tags
            .insert(id, serde_json::from_str::<Tag>(&data).map_err(err)?);
    }
    for (id, data) in read_map("views")? {
        document
            .views
            .insert(id, serde_json::from_str::<View>(&data).map_err(err)?);
    }
    let mut statement = connection
        .prepare("SELECT parent,child FROM links ORDER BY position")
        .map_err(err)?;
    document.links = statement
        .query_map([], |row| {
            Ok(Link {
                parent: row.get(0)?,
                child: row.get(1)?,
            })
        })
        .map_err(err)?
        .collect::<Result<_, _>>()
        .map_err(err)?;
    document.validate()?;
    Ok(document)
}

/// Replacement never truncates the previous document if a write fails.
pub fn publish(path: &Path, bytes: &[u8], overwrite: bool) -> Result<(), String> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut candidate = NamedTempFile::new_in(parent).map_err(err)?;
    candidate.write_all(bytes).map_err(err)?;
    candidate.as_file().sync_all().map_err(err)?;
    if overwrite {
        candidate.persist(path).map_err(|e| err(e.error))?;
    } else {
        candidate
            .persist_noclobber(path)
            .map_err(|e| err(e.error))?;
    }
    #[cfg(unix)]
    if let Ok(directory) = fs::File::open(parent) {
        let _ = directory.sync_all();
    }
    Ok(())
}

pub struct Session {
    pub document: Document,
    pub path: PathBuf,
    pub baseline: String,
    pub dirty: bool,
    pub persistence_failed: bool,
    pub recovery_path: PathBuf,
}
impl Session {
    pub fn open(path: PathBuf, recovery_dir: &Path) -> Result<Self, String> {
        Self::open_expected(path, recovery_dir, None)
    }
    pub fn open_expected(
        path: PathBuf,
        recovery_dir: &Path,
        expected_hash: Option<&str>,
    ) -> Result<Self, String> {
        let bytes = fs::read(&path).map_err(err)?;
        if expected_hash.is_some_and(|expected| expected != fingerprint(&bytes)) {
            return Err("Validated migration candidate changed before opening.".into());
        }
        crate::migration::reject_sidecars(&path).map_err(|e| e.0.to_string())?;
        crate::migration::require_current(&bytes)?;
        let document = decode(&bytes)?;
        let recovery_path = recovery_dir.join(format!(
            "{}-{}.ihtd",
            fingerprint(document.document_id.as_bytes()),
            fingerprint(path.to_string_lossy().as_bytes())
        ));
        Ok(Self {
            document,
            path,
            baseline: fingerprint(&bytes),
            dirty: false,
            persistence_failed: false,
            recovery_path,
        })
    }
    pub fn new(path: PathBuf, recovery_dir: &Path) -> Result<Self, String> {
        let document = Document::new(uuid::Uuid::new_v4().to_string());
        let bytes = encode(&document)?;
        publish(&path, &bytes, false)?;
        Self::open(path, recovery_dir)
    }
    pub fn restore_recovery(&mut self, recovery: &Path) -> Result<(), String> {
        self.restore_recovery_mode(recovery, true)
    }
    pub fn restore_recovery_if_newer(&mut self, recovery: &Path) -> Result<(), String> {
        self.restore_recovery_mode(recovery, false)
    }
    fn restore_recovery_mode(&mut self, recovery: &Path, force: bool) -> Result<(), String> {
        let bytes = fs::read(recovery).map_err(err)?;
        crate::migration::require_current(&bytes)?;
        let document = decode(&bytes)?;
        if document.document_id != self.document.document_id
            || (force && document.revision < self.document.revision)
        {
            return Err("Recovery does not belong to this working collection revision.".into());
        }
        if !force && document.revision <= self.document.revision {
            return Ok(());
        }
        self.document = document;
        self.dirty = true;
        Ok(())
    }
    pub fn restore_available(&mut self) -> Result<(), String> {
        if self.recovery_path.exists() {
            let bytes = fs::read(&self.recovery_path).map_err(err)?;
            crate::migration::require_current(&bytes)?;
            let recovered = decode(&bytes)?;
            if recovered.document_id == self.document.document_id
                && recovered.revision > self.document.revision
            {
                self.document = recovered;
                self.dirty = true;
            }
        }
        Ok(())
    }
    pub fn check_external(&mut self) -> Result<bool, String> {
        let bytes = fs::read(&self.path).map_err(|e| format!("Cannot read the open file: {e}"))?;
        let fingerprint = fingerprint(&bytes);
        if fingerprint == self.baseline {
            return Ok(false);
        }
        crate::migration::require_current(&bytes)?;
        let replacement = decode(&bytes)?;
        if self.dirty {
            return Err("The file changed while local edits are waiting to save. Use Save a copy as to preserve your edits.".into());
        }
        if replacement.document_id != self.document.document_id {
            return Err("The open file was replaced by a different collection. Open it explicitly to switch collections.".into());
        }
        if replacement.revision <= self.document.revision {
            return Err("The file contains an older or conflicting revision. Your open collection has been preserved; reopen the file explicitly if you want that version.".into());
        }
        self.document = replacement;
        self.baseline = fingerprint;
        Ok(true)
    }
    pub fn commit(&mut self, document: Document) -> Result<(), String> {
        let result = self.commit_inner(document);
        self.persistence_failed = result.is_err();
        result
    }
    fn commit_inner(&mut self, document: Document) -> Result<(), String> {
        let bytes = encode(&document)?;
        let current = fs::read(&self.path).map_err(err)?;
        if fingerprint(&current) != self.baseline {
            return Err("The file changed before this edit could be saved. Refresh the collection and try the edit again.".into());
        }
        if let Some(parent) = self.recovery_path.parent() {
            fs::create_dir_all(parent).map_err(err)?;
        }
        publish(&self.recovery_path, &bytes, true)?;
        self.document = document;
        self.dirty = true;
        // Check again after preparing recovery data; mounts can still hide remote changes.
        if fingerprint(&fs::read(&self.path).map_err(err)?) != self.baseline {
            return Err("External changes were detected during save. Your local edits are preserved; use Save a copy as.".into());
        }
        publish(&self.path,&bytes,true).map_err(|e| format!("Changes are preserved locally but could not be saved to the selected file: {e}. Use Retry or Save a copy as."))?;
        self.baseline = fingerprint(&bytes);
        self.dirty = false;
        self.persistence_failed = false;
        Ok(())
    }
    pub fn save_as(&mut self, path: PathBuf) -> Result<(), String> {
        let bytes = encode(&self.document)?;
        publish(&path, &bytes, false)?;
        self.path = path;
        self.recovery_path = self.recovery_path.parent().unwrap().join(format!(
            "{}-{}.ihtd",
            fingerprint(self.document.document_id.as_bytes()),
            fingerprint(self.path.to_string_lossy().as_bytes())
        ));
        self.baseline = fingerprint(&bytes);
        self.dirty = false;
        self.persistence_failed = false;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ihtd_core::model::ItemKind;
    #[test]
    fn copied_collections_have_independent_recovery_and_restore_only_their_own_edits() {
        let tmp = tempfile::tempdir().unwrap();
        let recovery_dir = tmp.path().join("recovery");
        fs::create_dir_all(&recovery_dir).unwrap();
        let first_path = tmp.path().join("first.ihtd");
        let mut first = Session::new(first_path.clone(), &recovery_dir).unwrap();
        let second_path = tmp.path().join("second.ihtd");
        fs::copy(&first_path, &second_path).unwrap();
        let mut second = Session::open(second_path.clone(), &recovery_dir).unwrap();
        assert_eq!(first.document.document_id, second.document.document_id);
        assert_ne!(first.recovery_path, second.recovery_path);
        let mut pending = first.document.clone();
        pending.revision += 1;
        publish(&first.recovery_path, &encode(&pending).unwrap(), true).unwrap();
        first.restore_available().unwrap();
        second.restore_available().unwrap();
        assert!(first.dirty);
        assert_eq!(first.document.revision, pending.revision);
        assert!(!second.dirty);
        let third_path = tmp.path().join("third.ihtd");
        first.save_as(third_path).unwrap();
        assert_ne!(first.recovery_path, second.recovery_path);
        assert!(!first.dirty);
    }
    #[test]
    fn failed_recovery_write_does_not_accept_an_edit_or_claim_it_is_durable() {
        let tmp = tempfile::tempdir().unwrap();
        let blocked = tmp.path().join("blocked");
        fs::write(&blocked, "not a directory").unwrap();
        let mut session = Session::new(tmp.path().join("tasks.ihtd"), &blocked).unwrap();
        let original = session.document.clone();
        let mut candidate = original.clone();
        candidate.revision += 1;
        assert!(session.commit(candidate).is_err());
        assert_eq!(session.document, original);
        assert!(!session.dirty);
        assert!(session.persistence_failed);
    }
    #[test]
    fn sqlite_roundtrip_is_self_contained_and_preserves_shared_ids() {
        let mut doc = Document::new("roundtrip".into());
        let a = doc.add_item(ItemKind::Folder, "A".into(), None).unwrap();
        let b = doc.add_item(ItemKind::Folder, "B".into(), None).unwrap();
        let t = doc
            .add_item(ItemKind::Task, "Same".into(), Some(a))
            .unwrap();
        doc.link(b, t).unwrap();
        let bytes = encode(&doc).unwrap();
        assert_eq!(&bytes[..16], b"SQLite format 3\0");
        assert_eq!(decode(&bytes).unwrap(), doc);
    }
    #[test]
    fn newer_replacement_reloads_but_corrupt_or_conflicting_file_cannot_discard_state() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("test.ihtd");
        let mut session = Session::new(path.clone(), tmp.path()).unwrap();
        let mut newer = session.document.clone();
        newer
            .add_item(ItemKind::Task, "Remote".into(), None)
            .unwrap();
        publish(&path, &encode(&newer).unwrap(), true).unwrap();
        assert!(session.check_external().unwrap());
        assert_eq!(session.document, newer);
        publish(&path, b"partial upload", true).unwrap();
        assert!(session.check_external().is_err());
        assert_eq!(session.document, newer);
    }
    #[test]
    fn external_edit_before_save_is_not_overwritten() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("test.ihtd");
        let mut s = Session::new(path.clone(), tmp.path()).unwrap();
        let mut local = s.document.clone();
        local
            .add_item(ItemKind::Task, "Local".into(), None)
            .unwrap();
        let mut remote = s.document.clone();
        remote
            .add_item(ItemKind::Task, "Remote".into(), None)
            .unwrap();
        let bytes = encode(&remote).unwrap();
        publish(&path, &bytes, true).unwrap();
        assert!(s.commit(local).is_err());
        assert_eq!(fs::read(path).unwrap(), bytes);
    }
    #[test]
    fn new_and_save_as_do_not_overwrite_existing_files() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("test.ihtd");
        let mut s = Session::new(path.clone(), tmp.path()).unwrap();
        let before = fs::read(&path).unwrap();
        assert!(Session::new(path.clone(), tmp.path()).is_err());
        assert!(s.save_as(path.clone()).is_err());
        assert_eq!(fs::read(path).unwrap(), before);
    }
    #[test]
    fn replacement_is_detected_even_when_size_and_timestamp_are_unchanged() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("file.ihtd");
        let mut s = Session::new(path.clone(), tmp.path()).unwrap();
        let mut first = s.document.clone();
        first
            .add_item(ItemKind::Task, "Alpha".into(), None)
            .unwrap();
        s.commit(first).unwrap();
        let before = fs::metadata(&path).unwrap();
        let mut next = s.document.clone();
        next.items.values_mut().next().unwrap().title = "Bravo".into();
        next.revision += 1;
        publish(&path, &encode(&next).unwrap(), true).unwrap();
        fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(fs::FileTimes::new().set_modified(before.modified().unwrap()))
            .unwrap();
        assert_eq!(fs::metadata(&path).unwrap().len(), before.len());
        assert!(s.check_external().unwrap());
        assert_eq!(s.document, next);
    }
    #[test]
    fn failed_replacement_keeps_destination_and_save_as_preserves_pending_state() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("file.ihtd");
        let mut s = Session::new(path.clone(), tmp.path()).unwrap();
        let mut candidate = s.document.clone();
        candidate
            .add_item(ItemKind::Task, "Keep me".into(), None)
            .unwrap();
        // A directory destination fails atomically without modifying its contents.
        let directory = tmp.path().join("directory.ihtd");
        fs::create_dir(&directory).unwrap();
        let marker = directory.join("marker");
        fs::write(&marker, "untouched").unwrap();
        assert!(publish(&directory, &encode(&candidate).unwrap(), true).is_err());
        assert_eq!(fs::read_to_string(marker).unwrap(), "untouched");
        // A failed publication after recovery is represented by dirty state; retry
        // and Save As use the exact same validated snapshot publication path.
        let recovery = encode(&candidate).unwrap();
        publish(&s.recovery_path, &recovery, true).unwrap();
        s.document = candidate.clone();
        s.dirty = true;
        let copy = tmp.path().join("recovered.ihtd");
        s.save_as(copy.clone()).unwrap();
        assert_eq!(decode(&fs::read(copy).unwrap()).unwrap(), candidate);
        assert!(!s.dirty);
    }
}

#[cfg(test)]
mod settings_tests {
    use super::*;
    use ihtd_core::settings::{CollectionSettings, IndicatorOverrides};
    #[test]
    fn distributed_schema_two_defaults_are_readonly_and_settings_roundtrip_preserves_everything_else(
    ) {
        let bytes = include_bytes!("../../../app/test/fixtures/migration-schema2.sqlite");
        let original = decode_preserving(bytes).unwrap();
        assert_eq!(original.collection_settings, CollectionSettings::default());
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("existing.ihtd");
        fs::write(&path, bytes).unwrap();
        let mut session = Session::open(path.clone(), &tmp.path().join("recovery")).unwrap();
        assert_eq!(fs::read(&path).unwrap(), bytes);
        let mut changed = session.document.clone();
        let old = changed.collection_settings.clone();
        let mut settings = old.clone();
        settings.tag_suggestion_count = 0;
        settings.tag_half_life_days = 7;
        settings.indicators.next_due_date = true;
        changed.set_collection_settings(&old, settings).unwrap();
        let parent = *changed.items.keys().next().unwrap();
        let view = *changed.views.keys().next().unwrap();
        let empty = IndicatorOverrides::default();
        changed
            .set_indicator_settings(
                parent,
                view,
                &empty,
                &empty,
                IndicatorOverrides {
                    total: Some(false),
                    ..empty.clone()
                },
                IndicatorOverrides {
                    low_priority: Some(true),
                    ..empty.clone()
                },
            )
            .unwrap();
        session.commit(changed.clone()).unwrap();
        let reopened = decode_preserving(&fs::read(path).unwrap()).unwrap();
        assert_eq!(reopened, changed);
        let mut preserved = reopened;
        preserved.collection_settings = original.collection_settings.clone();
        preserved.parent_indicator_defaults.clear();
        preserved
            .views
            .get_mut(&view)
            .unwrap()
            .preferences
            .get_mut(&parent)
            .unwrap()
            .indicators = empty;
        // Remove only the new preference entry if none existed in the source.
        if !original.views[&view].preferences.contains_key(&parent) {
            preserved
                .views
                .get_mut(&view)
                .unwrap()
                .preferences
                .remove(&parent);
        }
        preserved.revision = original.revision;
        assert_eq!(preserved, original);
    }
    #[test]
    fn malformed_optional_settings_are_not_silently_reset() {
        let doc = Document::new("settings".into());
        let file = NamedTempFile::new().unwrap();
        fs::write(file.path(), encode(&doc).unwrap()).unwrap();
        let c = Connection::open(file.path()).unwrap();
        c.execute(
            "UPDATE metadata SET value=?1 WHERE key='collection_settings'",
            [r#"{"tag_half_life_days":0}"#],
        )
        .unwrap();
        c.close().unwrap();
        assert!(decode(&fs::read(file.path()).unwrap()).is_err());
    }
}

#[cfg(test)]
mod sorting_preservation_tests {
    use super::*;
    use ihtd_core::sorting::{SortMode, SortSpec};
    #[test]
    fn distributed_files_default_to_manual_without_rewrite_and_new_choices_roundtrip() {
        let bytes = include_bytes!("../../../app/test/fixtures/migration-schema2.sqlite");
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("Original.ihtd");
        fs::write(&path, bytes).unwrap();
        let session = Session::open(path.clone(), &tmp.path().join("recovery")).unwrap();
        assert_eq!(fs::read(path).unwrap(), bytes);
        let mut d = session.document.clone();
        let before = d.clone();
        assert!(d.views.values().all(|v| v.sorting.is_empty()));
        d.set_sort(
            1,
            None,
            SortSpec::default(),
            SortSpec {
                mode: SortMode::DueDate,
                descending: true,
            },
        )
        .unwrap();
        let parent = *d.items.keys().next().unwrap();
        d.set_sort(
            1,
            Some(parent),
            SortSpec::default(),
            SortSpec {
                mode: SortMode::Priority,
                descending: true,
            },
        )
        .unwrap();
        let mut reopened = decode_preserving(&encode(&d).unwrap()).unwrap();
        assert_eq!(reopened, d);
        reopened.views.get_mut(&1).unwrap().sorting.clear();
        reopened.revision = before.revision;
        assert_eq!(reopened, before);
    }
}

#[cfg(test)]
mod tag_usage_preservation_tests {
    use super::*;
    #[test]
    fn old_files_have_no_invented_history_and_manual_history_roundtrips_without_other_changes() {
        let bytes = include_bytes!("../../../app/test/fixtures/migration-schema2.sqlite");
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("Original.ihtd");
        fs::write(&path, bytes).unwrap();
        let session = Session::open(path.clone(), &tmp.path().join("recovery")).unwrap();
        let before = session.document.clone();
        assert!(before.tag_usage.is_empty());
        assert_eq!(before.ranked_tags(1_800_000_000).unwrap(), [6]);
        assert_eq!(fs::read(&path).unwrap(), bytes);
        let mut changed = before.clone();
        changed.record_tag_assignments(&[6], 1_800_000_000).unwrap();
        let mut restored = decode_preserving(&encode(&changed).unwrap()).unwrap();
        assert_eq!(restored, changed);
        restored.tag_usage.clear();
        restored.revision = before.revision;
        assert_eq!(restored, before);
        let corrupt = tmp.path().join("Invalid.ihtd");
        fs::write(&corrupt, encode(&changed).unwrap()).unwrap();
        let connection = Connection::open(&corrupt).unwrap();
        connection
            .execute(
                "UPDATE metadata SET value=?1 WHERE key='tag_usage'",
                [r#"{"999":{"1800000000":1}}"#],
            )
            .unwrap();
        drop(connection);
        assert!(decode_preserving(&fs::read(corrupt).unwrap()).is_err());
    }
}
