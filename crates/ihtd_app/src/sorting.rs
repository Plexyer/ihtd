//! Read-only move planning binds the actual projection, paths and revision.
use ihtd_core::{model::Document, sorting::SortMode};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MoveRequest {
    pub view_id: i64,
    pub source_path: Vec<i64>,
    pub destination_path: Vec<i64>,
    pub before: Option<i64>,
    pub reorder: bool,
    pub completed: bool,
    pub expanded: BTreeSet<String>,
}
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MovePlan {
    pub request: MoveRequest,
    pub revision: u64,
    pub digest: String,
    pub switched_to_manual: bool,
}
fn row_path(path: &[i64]) -> String {
    path.iter()
        .map(i64::to_string)
        .collect::<Vec<_>>()
        .join("/")
}
pub fn prepare(doc: &Document, request: &MoveRequest) -> Result<Document, String> {
    doc.validate_occurrence(&request.source_path)?;
    if !request.destination_path.is_empty() {
        doc.validate_occurrence(&request.destination_path)?;
    }
    let source = request
        .source_path
        .last()
        .copied()
        .ok_or("Missing source occurrence")?;
    let parent = request.source_path.iter().rev().nth(1).copied();
    let destination = request.destination_path.last().copied();
    let rows =
        crate::presentation::outline(doc, request.view_id, request.completed, &request.expanded)?;
    if !rows
        .iter()
        .any(|r| r.path == row_path(&request.source_path))
    {
        return Err("The dragged occurrence is no longer displayed. Start the move again.".into());
    }
    let prefix = row_path(&request.destination_path);
    let displayed: Vec<_> = rows
        .iter()
        .filter(|r| {
            r.parent_id == destination
                && r.path
                    .rsplit_once('/')
                    .map(|(parent, _)| parent)
                    .unwrap_or("")
                    == prefix
        })
        .map(|r| r.id)
        .collect();
    if !request.reorder && request.before.is_some() {
        return Err("A container drop cannot specify a sibling position.".into());
    }
    let mut candidate = doc.clone();
    candidate.move_in_view(
        request.view_id,
        source,
        parent,
        destination,
        request.before,
        request.reorder,
        &displayed,
    )?;
    Ok(candidate)
}
pub fn preview(doc: &Document, request: MoveRequest) -> Result<MovePlan, String> {
    let candidate = prepare(doc, &request)?;
    let switched_to_manual = request.reorder
        && doc
            .sort_spec(request.view_id, request.destination_path.last().copied())?
            .mode
            != SortMode::Manual;
    Ok(MovePlan {
        request,
        revision: doc.revision,
        digest: crate::item_drafts::digest(&candidate)?,
        switched_to_manual,
    })
}
pub fn accepted_candidate(doc: &Document, plan: &MovePlan) -> Result<Document, String> {
    if doc.revision != plan.revision {
        return Err("The collection changed. Start the move again.".into());
    }
    let candidate = prepare(doc, &plan.request)?;
    if crate::item_drafts::digest(&candidate)? != plan.digest {
        return Err("The planned move changed. Nothing was moved.".into());
    }
    Ok(candidate)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ihtd_core::{
        model::ItemKind,
        sorting::{SortMode, SortSpec},
    };
    use serde_json::json;
    fn add(d: &mut Document, title: &str, parent: Option<i64>, priority: u8) -> i64 {
        let id = d.add_item(ItemKind::Task, title.into(), parent).unwrap();
        d.edit_item(id, title.into(), String::new(), None, priority, vec![])
            .unwrap();
        id
    }
    fn request(source: Vec<i64>, destination: Vec<i64>, before: Option<i64>) -> MoveRequest {
        MoveRequest {
            view_id: 1,
            source_path: source,
            destination_path: destination,
            before,
            reorder: true,
            completed: false,
            expanded: BTreeSet::from(["*".into()]),
        }
    }
    #[test]
    fn filtered_projection_drives_the_atomic_manual_transition_and_preserves_hidden_slots() {
        let mut d = Document::new("projection".into());
        let h = add(&mut d, "Hidden", None, 0);
        let z = add(&mut d, "Z", None, 1);
        let h2 = add(&mut d, "Hidden middle", None, 0);
        let b = add(&mut d, "B", None, 1);
        let a = add(&mut d, "A", None, 1);
        let view_id = d
            .add_view(
                "Visible".into(),
                serde_json::from_value(json!({"op":"priority","comparison":"ge","value":1}))
                    .unwrap(),
            )
            .unwrap();
        d.set_sort(
            view_id,
            None,
            SortSpec::default(),
            SortSpec {
                mode: SortMode::Title,
                descending: false,
            },
        )
        .unwrap();
        let old = d.clone();
        let mut movement = request(vec![z], vec![], Some(b));
        movement.view_id = view_id;
        let plan = preview(&d, movement).unwrap();
        assert!(plan.switched_to_manual);
        assert_eq!(d, old);
        let candidate = accepted_candidate(&d, &plan).unwrap();
        assert_eq!(candidate.roots(), [h, a, h2, z, b]);
        assert_eq!(candidate.revision, d.revision + 1);
        assert_eq!(candidate.items, d.items);
        assert_eq!(candidate.tags, d.tags);
        assert_eq!(
            crate::storage::decode(&crate::storage::encode(&candidate).unwrap()).unwrap(),
            candidate
        );
        let mut tampered = plan.clone();
        tampered.digest = "tampered".into();
        assert!(accepted_candidate(&d, &tampered).is_err());
        d.add_tag("Concurrent edit".into()).unwrap();
        assert!(accepted_candidate(&d, &plan).is_err());
    }
    #[test]
    fn wrong_tab_missing_paths_hidden_before_and_linked_parent_moves_fail_without_mutation() {
        let mut d = Document::new("guard".into());
        let a = add(&mut d, "A", None, 0);
        let b = add(&mut d, "B", None, 0);
        let f = add(&mut d, "F", Some(a), 0);
        let child = add(&mut d, "Child", Some(f), 0);
        let other = add(&mut d, "Other", Some(f), 0);
        d.link(b, f).unwrap();
        let old = d.clone();
        let mut moved = request(vec![a, f, child], vec![], None);
        assert!(preview(&d, moved.clone())
            .unwrap_err()
            .contains("independent copy"));
        assert_eq!(d, old);
        moved.destination_path = vec![a, f];
        moved.completed = true;
        assert!(preview(&d, moved.clone()).is_err());
        moved.completed = false;
        moved.destination_path = vec![999];
        assert!(preview(&d, moved).is_err());
        let plan = preview(&d, request(vec![a, f, child], vec![a, f], None)).unwrap();
        let candidate = accepted_candidate(&d, &plan).unwrap();
        assert_eq!(candidate.manual_siblings(Some(f)), [other, child]);
        assert_eq!(candidate.appearance_counts()[&child], "2");
    }
    #[test]
    fn source_and_destination_paths_distinguish_shared_parent_visibility() {
        let mut d = Document::new("paths".into());
        let a = add(&mut d, "A", None, 0);
        let b = add(&mut d, "B", None, 0);
        let f = add(&mut d, "F", Some(a), 0);
        d.link(b, f).unwrap();
        let one = add(&mut d, "Z", Some(f), 0);
        let two = add(&mut d, "A", Some(f), 0);
        d.set_sort(
            1,
            Some(f),
            SortSpec::default(),
            SortSpec {
                mode: SortMode::Title,
                descending: false,
            },
        )
        .unwrap();
        let plan = preview(&d, request(vec![b, f, one], vec![b, f], Some(two))).unwrap();
        let candidate = accepted_candidate(&d, &plan).unwrap();
        assert_eq!(candidate.manual_siblings(Some(f)), [one, two]);
        // IDs appear on two paths, but the projection must contain each once.
        assert_eq!(candidate.appearance_counts()[&one], "2");
    }
}
