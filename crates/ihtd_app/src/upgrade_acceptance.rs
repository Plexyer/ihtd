//! Acceptance against files emitted by the actual published v0.2.5 model/encoder.
use crate::{migration, storage};
use serde_json::{json, Value};
use std::fs;

#[test]
fn published_model_snapshots_preserve_the_entire_projection_before_and_after_conversion() {
    for (name, bytes, expected) in [
        (
            "intact",
            include_bytes!("../../../app/test/fixtures/upgrade-0.2.5/intact.sqlite").as_slice(),
            include_str!("../../../app/test/fixtures/upgrade-0.2.5/intact.json"),
        ),
        (
            "customized",
            include_bytes!("../../../app/test/fixtures/upgrade-0.2.5/customized.sqlite").as_slice(),
            include_str!("../../../app/test/fixtures/upgrade-0.2.5/customized.json"),
        ),
        (
            "deleted-default",
            include_bytes!("../../../app/test/fixtures/upgrade-0.2.5/deleted-default.sqlite")
                .as_slice(),
            include_str!("../../../app/test/fixtures/upgrade-0.2.5/deleted-default.json"),
        ),
        (
            "pending",
            include_bytes!("../../../app/test/fixtures/upgrade-0.2.5/pending.sqlite").as_slice(),
            include_str!("../../../app/test/fixtures/upgrade-0.2.5/pending.json"),
        ),
    ] {
        let expected: Value = serde_json::from_str(expected).unwrap();
        let decoded = storage::decode_preserving(bytes).unwrap();
        assert_eq!(
            serde_json::to_value(&decoded).unwrap(),
            expected,
            "{name}: loading changed the published document projection"
        );
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("Original.ihtd");
        fs::write(&source, bytes).unwrap();
        let probe = migration::execute(&json!({"action":"probe","source":source}))
            .ok()
            .unwrap();
        assert_eq!(probe["needed"], name != "intact");
        if name == "intact" {
            assert!(storage::Session::open(source.clone(), dir.path()).is_ok());
        } else {
            assert!(storage::Session::open(source.clone(), dir.path()).is_err());
            let candidate = dir.path().join("candidate.ihtd");
            migration::execute(
                &json!({"action":"prepare","source":source,"candidate":candidate,
                "expected_hash":storage::fingerprint(bytes)}),
            )
            .ok()
            .unwrap();
            let after = storage::decode_preserving(&fs::read(candidate).unwrap()).unwrap();
            let id = decoded.next_id;
            let mut planned = expected.clone();
            planned["all_tasks_view_id"] = json!(id);
            planned["next_id"] = json!(id + 1);
            planned["revision"] = json!(decoded.revision + 1);
            planned["views"][id.to_string()] = json!({"id":id,"name":"All tasks",
                "filter":{"op":"all"},"preferences":{}});
            assert_eq!(
                serde_json::to_value(after).unwrap(),
                planned,
                "{name}: migration changed fields outside its explicit plan"
            );
        }
        assert_eq!(fs::read(source).unwrap(), bytes);
    }
}
