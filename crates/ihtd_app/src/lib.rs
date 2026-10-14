pub mod export;
pub mod filesystem;
pub mod presentation;
pub mod storage;

use ihtd_core::{
    graph::ItemId,
    model::{ContainerPreferences, ItemKind},
};
use serde_json::{json, Value};
use std::{collections::BTreeSet, path::PathBuf};
use storage::Session;

pub struct Backend {
    session: Option<Session>,
    recovery_dir: PathBuf,
}
impl Default for Backend {
    fn default() -> Self {
        Self {
            session: None,
            recovery_dir: std::env::temp_dir().join("ihtd-recovery"),
        }
    }
}
fn number(v: &Value, key: &str) -> Result<i64, String> {
    v[key]
        .as_i64()
        .ok_or_else(|| format!("Missing or invalid {key}"))
}
fn string(v: &Value, key: &str) -> Result<String, String> {
    v[key]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| format!("Missing {key}"))
}
fn flag(v: &Value, key: &str) -> bool {
    v[key].as_bool().unwrap_or(false)
}
fn decode<T: serde::de::DeserializeOwned>(v: &Value) -> Result<T, String> {
    serde_json::from_value(v.clone()).map_err(|e| e.to_string())
}

impl Backend {
    pub fn execute(&mut self, request: &str) -> String {
        if let Ok(value) = serde_json::from_str::<Value>(request) {
            if value["op"] == "filesystem" {
                return match filesystem::execute(&value) {
                    Ok(data) => json!({"ok":true,"data":data}).to_string(),
                    Err(filesystem::Failure(code)) => {
                        json!({"ok":false,"error_code":code,"error":code}).to_string()
                    }
                };
            }
        }
        let result = serde_json::from_str::<Value>(request)
            .map_err(|e| e.to_string())
            .and_then(|v| self.command(v));
        match result {
            Ok(data) => json!({"ok":true,"data":data,"snapshot":self.snapshot()}).to_string(),
            Err(error) => json!({"ok":false,"error":error,"snapshot":self.snapshot()}).to_string(),
        }
    }
    fn snapshot(&self) -> Value {
        match &self.session {
            None => Value::Null,
            Some(s) => {
                json!({"document":s.document,"path":s.path,"dirty":s.dirty,"persistence_failed":s.persistence_failed,"recovery_path":s.recovery_path,"completion":s.document.completion_states().unwrap_or_default()})
            }
        }
    }
    fn command(&mut self, request: Value) -> Result<Value, String> {
        let op = string(&request, "op")?;
        match op.as_str() {
            "initialize" => {
                self.recovery_dir = PathBuf::from(string(&request, "recovery_dir")?);
                std::fs::create_dir_all(&self.recovery_dir).map_err(|e| e.to_string())?;
                return Ok(json!({}));
            }
            "snapshot" => return Ok(json!({})),
            "open" | "new" => {
                if self.session.as_ref().map(|s| s.dirty).unwrap_or(false)
                    && !request
                        .get("preserve_pending")
                        .and_then(Value::as_bool)
                        .unwrap_or(false)
                {
                    return Err("Save your pending edits with Retry or Save a copy as before switching files.".into());
                }
                let path = PathBuf::from(string(&request, "path")?);
                let mut next = if op == "new" {
                    Session::new(path, &self.recovery_dir)?
                } else {
                    Session::open(path, &self.recovery_dir)?
                };
                if op == "open" {
                    if let Some(recovery) = request.get("recovery_path").and_then(Value::as_str) {
                        next.restore_recovery(std::path::Path::new(recovery))?;
                    }
                    if request
                        .get("recover_local")
                        .and_then(Value::as_bool)
                        .unwrap_or(false)
                    {
                        next.restore_available()?;
                    }
                }
                self.session = Some(next);
                return Ok(json!({}));
            }
            _ => {}
        }
        let session = self
            .session
            .as_mut()
            .ok_or("Open or create a collection first")?;
        match op.as_str() {
            "copy" => {
                let path = PathBuf::from(string(&request, "path")?);
                storage::publish(&path, &storage::encode(&session.document)?, false)?;
                return Ok(json!({}));
            }
            "poll" => return Ok(json!({"reloaded":session.check_external()?})),
            "retry" => {
                session.commit(session.document.clone())?;
                return Ok(json!({}));
            }
            "save_as" => {
                session.save_as(PathBuf::from(string(&request, "path")?))?;
                return Ok(json!({}));
            }
            "export" => {
                let path = PathBuf::from(string(&request, "path")?);
                if path == session.path {
                    return Err("Choose an export path different from the open document".into());
                }
                let content = export::export(&session.document, &string(&request, "format")?)?;
                storage::publish(&path, content.as_bytes(), false)?;
                return Ok(json!({}));
            }
            "query" => {
                let expanded: BTreeSet<String> = decode(&request["expanded"])?;
                return Ok(
                    json!({"rows":presentation::outline(&session.document,number(&request,"view_id")?,flag(&request,"completed_only"),&expanded)?}),
                );
            }
            "creation_defaults" => {
                let view = session
                    .document
                    .views
                    .get(&number(&request, "view_id")?)
                    .ok_or("View not found")?;
                return serde_json::to_value(view.filter.creation_defaults(&session.document))
                    .map_err(|e| e.to_string());
            }
            _ => {}
        }
        // Refresh a newly exposed external revision before accepting a mutation.
        // The UI must retry from the refreshed snapshot instead of applying stale editor values.
        if session.check_external()? {
            return Err("A newer external file was loaded. Review the updated task, then apply your edit again.".into());
        }
        if let Some(expected) = request["expected_revision"].as_u64() {
            if expected != session.document.revision {
                return Err("This edit was based on an older document revision. Load the latest saved values before editing again; your draft has not overwritten the newer file.".into());
            }
        }
        let mut document = session.document.clone();
        let old_revision = document.revision;
        let data = match op.as_str() {
            "add_item" => {
                let view_id = number(&request, "view_id")?;
                let filter = document
                    .views
                    .get(&view_id)
                    .ok_or("View not found")?
                    .filter
                    .clone();
                let defaults = filter.creation_defaults(&document);
                let kind = decode::<ItemKind>(&request["kind"])?;
                let parent = request["parent_id"].as_i64();
                let id = document.add_item(kind, string(&request, "title")?, parent)?;
                let notes = request["notes"]
                    .as_str()
                    .map(str::to_owned)
                    .or(defaults.notes)
                    .unwrap_or_default();
                let due = if request.get("due_date").is_some() {
                    request["due_date"].as_str().map(str::to_owned)
                } else {
                    defaults.due_date
                };
                let priority = request["priority"]
                    .as_u64()
                    .map(|p| u8::try_from(p).map_err(|_| "Invalid priority".to_string()))
                    .transpose()?
                    .or(defaults.priority)
                    .unwrap_or(0);
                let tags = if request.get("tag_ids").is_some() {
                    decode(&request["tag_ids"])?
                } else {
                    defaults.tag_ids
                };
                document.edit_item(id, string(&request, "title")?, notes, due, priority, tags)?;
                for p in defaults.parent_ids {
                    if !document
                        .links
                        .iter()
                        .any(|l| l.parent == p && l.child == id)
                    {
                        document.link(p, id)?;
                    }
                }
                if flag(&request, "completed") && kind == ItemKind::Task {
                    document.set_completed(id, true, true)?;
                }
                if !filter.matches(&document.items[&id], &document) {
                    return Err("This item does not meet the view's complete filter. Supply the required title, notes, tags, date, priority, or parent placement before creating it.".into());
                }
                json!({"id":id})
            }
            "edit_item" => {
                document.edit_item(
                    number(&request, "id")?,
                    string(&request, "title")?,
                    string(&request, "notes")?,
                    request["due_date"].as_str().map(str::to_owned),
                    u8::try_from(number(&request, "priority")?).map_err(|_| "Invalid priority")?,
                    decode(&request["tag_ids"])?,
                )?;
                json!({})
            }
            "link" => {
                document.link(number(&request, "parent")?, number(&request, "child")?)?;
                json!({})
            }
            "move_item" => {
                document.move_item(
                    number(&request, "id")?,
                    request["source_parent"].as_i64(),
                    request["destination_parent"].as_i64(),
                    request["before"].as_i64(),
                )?;
                json!({})
            }
            "unlink" => {
                document.unlink(number(&request, "parent")?, number(&request, "child")?)?;
                json!({})
            }
            "convert_kind" => {
                document.convert_kind(number(&request, "id")?, decode(&request["kind"])?)?;
                json!({})
            }
            "set_auto_complete" => {
                document.set_auto_complete(number(&request, "id")?, flag(&request, "enabled"))?;
                json!({})
            }
            "set_completed" => {
                let id = number(&request, "id")?;
                let completed = flag(&request, "completed");
                if completed && !flag(&request, "confirm_descendants") {
                    let graph = document.build_graph()?;
                    let count = graph
                        .descendants(ItemId::new(id).map_err(|e| e.to_string())?)
                        .map_err(|e| e.to_string())?
                        .iter()
                        .filter(|c| {
                            document.items[&c.get()].kind == ItemKind::Task
                                && !document.items[&c.get()].completed
                        })
                        .count();
                    if count > 0 {
                        return Ok(json!({"confirmation_required":true,"descendant_count":count}));
                    }
                }
                document.set_completed(id, completed, flag(&request, "confirm_descendants"))?;
                json!({})
            }
            "add_tag" => json!({"id":document.add_tag(string(&request,"name")?)?}),
            "rename_tag" => {
                document.rename_tag(number(&request, "id")?, string(&request, "name")?)?;
                json!({})
            }
            "add_view" => {
                json!({"id":document.add_view(string(&request,"name")?,decode(&request["filter"])?)?})
            }
            "edit_view" => {
                document.edit_view(
                    number(&request, "id")?,
                    string(&request, "name")?,
                    decode(&request["filter"])?,
                )?;
                json!({})
            }
            "remove_view" => {
                document.remove_view(number(&request, "id")?)?;
                json!({})
            }
            "set_preferences" => {
                document.set_container_preferences(
                    number(&request, "view_id")?,
                    number(&request, "item_id")?,
                    decode::<ContainerPreferences>(&request["preferences"])?,
                )?;
                json!({})
            }
            _ => return Err(format!("Unknown operation: {op}")),
        };
        document.revision = old_revision.checked_add(1).ok_or("Revision exhausted")?;
        session.commit(document)?;
        Ok(data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn execute(b: &mut Backend, v: Value) -> Value {
        serde_json::from_str(&b.execute(&v.to_string())).unwrap()
    }
    #[test]
    fn filtered_creation_is_atomic_and_saves_every_accepted_change() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("file.ihtd");
        let mut b = Backend {
            session: None,
            recovery_dir: tmp.path().join("recovery"),
        };
        assert_eq!(execute(&mut b, json!({"op":"new","path":path}))["ok"], true);
        let v=execute(&mut b,json!({"op":"add_view","name":"Before","filter":{"op":"due","comparison":"before","value":"2026-10-01"}}))["data"]["id"].as_i64().unwrap();
        let before = std::fs::read(&path).unwrap();
        let failed = execute(
            &mut b,
            json!({"op":"add_item","kind":"task","title":"Missing date","view_id":v}),
        );
        assert_eq!(failed["ok"], false);
        assert_eq!(std::fs::read(&path).unwrap(), before);
        let ok = execute(
            &mut b,
            json!({"op":"add_item","kind":"task","title":"Valid","view_id":v,"due_date":"2026-09-30"}),
        );
        assert_eq!(ok["ok"], true);
        assert_eq!(
            storage::decode(&std::fs::read(path).unwrap())
                .unwrap()
                .items
                .len(),
            1
        );
    }
}
