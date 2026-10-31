//! Executed only against the pinned v0.2.5 workspace, never today's encoder.
use ihtd_app::storage;
use ihtd_core::{
    filter::FilterExpr,
    model::{ContainerPreferences, Document, ItemKind},
};
use serde_json::json;
use std::{fs, path::Path};

fn save(root: &Path, name: &str, doc: &Document) {
    let path = root.join(format!("{name}.sqlite"));
    storage::publish(&path, &storage::encode(doc).unwrap(), false).unwrap();
    // The old app itself must be able to reopen every produced snapshot.
    let reopened = storage::Session::open(path, &root.join("private-recovery")).unwrap();
    assert_eq!(reopened.document, *doc);
    fs::write(
        root.join(format!("{name}.json")),
        serde_json::to_vec_pretty(doc).unwrap(),
    )
    .unwrap();
}
fn main() {
    let output = std::env::args().nth(1).expect("output directory");
    let output = Path::new(&output);
    fs::create_dir_all(output).unwrap();
    let mut doc = Document::new("synthetic-released-0.2.5-collection".into());
    let travel = doc.add_tag("Travel / 旅行".into()).unwrap();
    let urgent = doc.add_tag("Important".into()).unwrap();
    let trip = doc
        .add_item(ItemKind::Folder, "Japan trip".into(), None)
        .unwrap();
    let home = doc.add_item(ItemKind::Folder, "Home".into(), None).unwrap();
    let passport = doc
        .add_item(ItemKind::Task, "Pack passport".into(), Some(trip))
        .unwrap();
    doc.edit_item(
        passport,
        "Pack passport".into(),
        "Original notes 日本\nSecond line: insurance & tickets.".into(),
        Some("2026-12-01".into()),
        3,
        vec![travel],
    )
    .unwrap();
    doc.link(home, passport).unwrap();
    let hotel = doc
        .add_item(ItemKind::Task, "Book hotel".into(), Some(trip))
        .unwrap();
    doc.edit_item(
        hotel,
        "Book hotel".into(),
        "Keep this independent item unchanged.".into(),
        Some("2026-11-05".into()),
        2,
        vec![travel, urgent],
    )
    .unwrap();
    let nested = doc
        .add_item(ItemKind::Folder, "Packing".into(), Some(trip))
        .unwrap();
    let adapter = doc
        .add_item(ItemKind::Task, "Travel adapter".into(), Some(nested))
        .unwrap();
    doc.edit_item(
        adapter,
        "Travel adapter".into(),
        "Nested item".into(),
        None,
        1,
        vec![],
    )
    .unwrap();
    let automatic = doc
        .add_item(ItemKind::Task, "Completed automatic parent".into(), None)
        .unwrap();
    let completed = doc
        .add_item(ItemKind::Task, "Finished child".into(), Some(automatic))
        .unwrap();
    doc.set_completed(completed, true, true).unwrap();
    doc.set_auto_complete(automatic, true).unwrap();
    let rule: FilterExpr = serde_json::from_value(json!({"op":"and","rules":[
      {"op":"tag","tag_id":travel},{"op":"or","rules":[
        {"op":"priority","comparison":"ge","value":2},
        {"op":"folder","folder_id":trip,"recursive":true}]}]}))
    .unwrap();
    let custom = doc
        .add_view("Travel priorities".into(), rule.clone())
        .unwrap();
    doc.set_container_preferences(
        custom,
        trip,
        ContainerPreferences {
            hide_completed: Some(false),
            inherit_hide_completed: true,
            folder_hidden: false,
            reappear_on_new: true,
        },
    )
    .unwrap();
    let deleted = doc
        .add_item(ItemKind::Folder, "Removed container".into(), None)
        .unwrap();
    let broken = doc
        .add_view(
            "Retained deleted-container rule".into(),
            serde_json::from_value(json!({"op":"folder","folder_id":deleted,"recursive":true}))
                .unwrap(),
        )
        .unwrap();
    let preview = doc.preview_removal(deleted, None).unwrap();
    doc.remove_placement(&preview, true).unwrap();
    save(output, "intact", &doc);
    doc.edit_view(1, "My old customized default".into(), rule)
        .unwrap();
    save(output, "customized", &doc);
    let mut deleted_default = doc.clone();
    deleted_default.remove_view(1).unwrap();
    save(output, "deleted-default", &deleted_default);
    let mut pending = doc.clone();
    pending
        .edit_item(
            passport,
            "Passport (unpublished edit)".into(),
            "Unpublished notes 保険\nRetain this working/recovery version.".into(),
            Some("2026-12-01".into()),
            3,
            vec![travel],
        )
        .unwrap();
    save(output, "pending", &pending);
    fs::write(
        output.join("roles.json"),
        serde_json::to_vec_pretty(&json!({
            "travel_tag":travel,"urgent_tag":urgent,"trip":trip,"home":home,
            "passport":passport,"hotel":hotel,"nested":nested,"adapter":adapter,
            "automatic_parent":automatic,"completed_child":completed,
            "custom_view":custom,"deleted_container":deleted,"broken_view":broken
        }))
        .unwrap(),
    )
    .unwrap();
}
