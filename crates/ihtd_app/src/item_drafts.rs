//! Atomic item draft commits, separate from persistence of unfinished UI drafts.
use ihtd_core::model::{Document, ItemKind};
use serde_json::{json, Value};

fn string(v: &Value, key: &str) -> Result<String, String> {
    v[key]
        .as_str()
        .map(str::to_owned)
        .ok_or_else(|| format!("Missing {key}"))
}
pub fn digest(document: &Document) -> Result<String, String> {
    Ok(crate::storage::fingerprint(
        &serde_json::to_vec(document).map_err(|e| e.to_string())?,
    ))
}
pub fn prepare(source: &Document, request: &Value) -> Result<(Document, i64), String> {
    let mut doc = source.clone();
    let existing_id = match request.get("id") {
        None | Some(Value::Null) => None,
        Some(value) => Some(value.as_i64().ok_or("Invalid draft item ID")?),
    };
    let parent = match request.get("parent_id") {
        None | Some(Value::Null) => None,
        Some(value) => Some(value.as_i64().ok_or("Invalid parent placement")?),
    };
    let id = if let Some(id) = existing_id {
        let current = doc
            .items
            .get(&id)
            .ok_or("This item no longer exists. Your draft has been retained.")?;
        let mut observed = serde_json::to_value(current).map_err(|e| e.to_string())?;
        let mut expected = request["expected_item"].clone();
        // Manual completion is an immediate hierarchy action, not an editable
        // draft field on existing items. Preserve it without treating it as a
        // competing title/notes edit; Save never writes this request field.
        observed
            .as_object_mut()
            .ok_or("Invalid item baseline")?
            .remove("completed");
        expected
            .as_object_mut()
            .ok_or("Invalid item baseline")?
            .remove("completed");
        if observed != expected {
            return Err("This item changed while you were editing. Your draft has been retained; review the latest saved values before saving.".into());
        }
        id
    } else {
        let view = request["view_id"]
            .as_i64()
            .and_then(|id| doc.views.get(&id))
            .ok_or("The creation view no longer exists.")?;
        if serde_json::to_value(view).map_err(|e| e.to_string())? != request["expected_view"] {
            return Err("The creation view changed. Your draft has been retained.".into());
        }
        let kind: ItemKind =
            serde_json::from_value(request["kind"].clone()).map_err(|e| e.to_string())?;
        let id = doc.add_item(kind, string(request, "title")?, parent)?;
        let defaults = view_filter(source, request)?.creation_defaults(source);
        for parent in defaults.parent_ids {
            if !doc
                .links
                .iter()
                .any(|l| l.parent == parent && l.child == id)
            {
                doc.link(parent, id)?;
            }
        }
        id
    };
    doc.edit_item(
        id,
        string(request, "title")?,
        string(request, "notes")?,
        request["due_date"].as_str().map(str::to_owned),
        request["priority"]
            .as_u64()
            .and_then(|n| u8::try_from(n).ok())
            .ok_or("Invalid priority")?,
        serde_json::from_value(request["tag_ids"].clone()).map_err(|e| e.to_string())?,
    )?;
    let auto = request["auto_complete"].as_bool().unwrap_or(false);
    if doc.items[&id].auto_complete != auto {
        doc.set_auto_complete(id, auto)?;
    }
    if existing_id.is_none() {
        if request["completed"].as_bool() == Some(true) && doc.items[&id].kind == ItemKind::Task {
            doc.set_completed(id, true, true)?;
        }
        if !view_filter(source, request)?.matches(&doc.items[&id], &doc) {
            return Err(
                "This item does not meet the view's complete filter. Your draft has been retained."
                    .into(),
            );
        }
    }
    doc.revision = source.revision.checked_add(1).ok_or("Revision exhausted")?;
    doc.validate()?;
    Ok((doc, id))
}
fn view_filter<'a>(
    doc: &'a Document,
    request: &Value,
) -> Result<&'a ihtd_core::filter::FilterExpr, String> {
    doc.views
        .get(&request["view_id"].as_i64().ok_or("Missing view")?)
        .map(|v| &v.filter)
        .ok_or("View not found".into())
}
pub fn preview(source: &Document, request: &Value) -> Result<Value, String> {
    let (doc, id) = prepare(source, request)?;
    Ok(json!({"id":id,"digest":digest(&doc)?,"revision":source.revision}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn staged_fields_and_auto_completion_commit_atomically_and_reject_stale_edits() {
        let mut doc = Document::new("test".into());
        let id = doc.add_item(ItemKind::Task, "Saved".into(), None).unwrap();
        let request = json!({"id":id,"expected_item":doc.items[&id],"title":"Draft","notes":"private notes","due_date":"2026-12-01","priority":3,"tag_ids":[],"auto_complete":true});
        let (saved, _) = prepare(&doc, &request).unwrap();
        assert_eq!(doc.items[&id].title, "Saved");
        assert_eq!(saved.items[&id].title, "Draft");
        assert!(saved.items[&id].auto_complete);
        assert!(prepare(&saved, &request).is_err());
        let mut invalid = request.clone();
        invalid["priority"] = json!(9);
        assert!(prepare(&doc, &invalid).is_err());
        assert_eq!(doc.items[&id].title, "Saved");
    }
    #[test]
    fn creation_preserves_filter_hints_and_preview_receipt_and_rejects_stale_view() {
        let mut doc = Document::new("test".into());
        let tag = doc.add_tag("Travel".into()).unwrap();
        let view = doc
            .add_view(
                "Travel view".into(),
                ihtd_core::filter::FilterExpr::Tag { tag_id: tag },
            )
            .unwrap();
        let request = json!({"id":null,"view_id":view,"expected_view":doc.views[&view],"kind":"task","title":"Passport","notes":"","due_date":null,"priority":0,"tag_ids":[tag],"auto_complete":false,"completed":false,"parent_id":null});
        let plan = preview(&doc, &request).unwrap();
        let (created, id) = prepare(&doc, &request).unwrap();
        assert_eq!(plan["digest"], digest(&created).unwrap());
        assert_eq!(created.items[&id].tag_ids, vec![tag]);
        assert_eq!(doc.items.len(), 0);
        doc.views.get_mut(&view).unwrap().name = "Changed".into();
        assert!(prepare(&doc, &request).is_err());
    }
    #[test]
    fn inherited_completion_failure_does_not_partially_commit_text() {
        let mut doc = Document::new("test".into());
        let parent = doc.add_item(ItemKind::Task, "Parent".into(), None).unwrap();
        let child = doc
            .add_item(ItemKind::Task, "Child".into(), Some(parent))
            .unwrap();
        doc.set_auto_complete(child, true).unwrap();
        doc.set_auto_complete(parent, true).unwrap();
        let original = doc.clone();
        let request = json!({"id":child,"expected_item":doc.items[&child],"kind":"task","title":"Not accepted","notes":"","due_date":null,"priority":0,"tag_ids":[],"auto_complete":false});
        assert!(prepare(&doc, &request).is_err());
        assert_eq!(doc, original);
    }
    #[test]
    fn independent_manual_completion_is_preserved_when_saving_notes() {
        let mut doc = Document::new("test".into());
        let id = doc.add_item(ItemKind::Task, "Task".into(), None).unwrap();
        let baseline = doc.items[&id].clone();
        doc.set_completed(id, true, true).unwrap();
        let request = json!({"id":id,"expected_item":baseline,"title":"Task","notes":"Draft notes","due_date":null,"priority":0,"tag_ids":[],"auto_complete":false,"completed":false});
        let (saved, _) = prepare(&doc, &request).unwrap();
        assert!(saved.items[&id].completed);
        assert_eq!(saved.items[&id].notes, "Draft notes");
    }
    #[test]
    fn malformed_id_and_parent_cannot_be_interpreted_as_new_or_top_level() {
        let doc = Document::new("test".into());
        for request in [
            json!({"id":"not-an-id"}),
            json!({"id":null,"parent_id":"not-a-parent"}),
        ] {
            assert!(prepare(&doc, &request).is_err());
        }
        assert!(doc.items.is_empty());
    }
}
