//! Placement-aware removal shared by every UI and storage adapter.
use std::collections::{BTreeMap, BTreeSet, VecDeque};

use serde::{Deserialize, Serialize};

use crate::model::Document;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RemovalAction {
    Unlink,
    Delete,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Placements {
    pub parents: Vec<i64>,
    pub root: bool,
    pub count: usize,
}

/// An exact, revision-bound preview. Executing stale or altered previews fails
/// without mutation, even if the action changed from Unlink to Delete.
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct RemovalPreview {
    pub document_id: String,
    pub revision: u64,
    pub id: i64,
    pub parent: Option<i64>,
    pub action: RemovalAction,
    pub deleted_ids: Vec<i64>,
    /// Surviving branches directly attached to deleted nodes. Their children
    /// survive as well unless they independently lose all remaining placements.
    pub retained_child_ids: Vec<i64>,
    pub affected_view_ids: Vec<i64>,
}

impl Document {
    pub fn placements(&self) -> BTreeMap<i64, Placements> {
        let roots: BTreeSet<_> = self.roots().into_iter().collect();
        let mut result: BTreeMap<_, _> = self
            .items
            .keys()
            .map(|&id| {
                (
                    id,
                    Placements {
                        parents: vec![],
                        root: roots.contains(&id),
                        count: usize::from(roots.contains(&id)),
                    },
                )
            })
            .collect();
        for link in &self.links {
            if let Some(placements) = result.get_mut(&link.child) {
                placements.parents.push(link.parent);
                placements.count += 1;
            }
        }
        result
    }

    pub fn preview_removal(&self, id: i64, parent: Option<i64>) -> Result<RemovalPreview, String> {
        let placements = self.placements();
        let placement = placements.get(&id).ok_or("This item no longer exists")?;
        let exists = match parent {
            Some(parent) => placement.parents.contains(&parent),
            None => placement.root,
        };
        if !exists {
            return Err("This placement no longer exists. Review the updated collection.".into());
        }
        let action = if placement.count > 1 {
            RemovalAction::Unlink
        } else {
            RemovalAction::Delete
        };
        let mut deleted = BTreeSet::new();
        let mut retained = BTreeSet::new();
        if action == RemovalAction::Delete {
            let mut children: BTreeMap<i64, Vec<i64>> = BTreeMap::new();
            for link in &self.links {
                children.entry(link.parent).or_default().push(link.child);
            }
            let mut remaining: BTreeMap<_, _> =
                placements.iter().map(|(&id, p)| (id, p.count)).collect();
            let mut queue = VecDeque::from([id]);
            deleted.insert(id);
            while let Some(current) = queue.pop_front() {
                for &child in children.get(&current).into_iter().flatten() {
                    let count = remaining.get_mut(&child).ok_or("Invalid child placement")?;
                    *count -= 1;
                    if *count == 0 && deleted.insert(child) {
                        queue.push_back(child);
                    }
                }
            }
            for link in &self.links {
                if deleted.contains(&link.parent) && !deleted.contains(&link.child) {
                    retained.insert(link.child);
                }
            }
        }
        Ok(RemovalPreview {
            document_id: self.document_id.clone(),
            revision: self.revision,
            id,
            parent,
            action,
            deleted_ids: deleted.iter().copied().collect(),
            retained_child_ids: retained.into_iter().collect(),
            affected_view_ids: self
                .views
                .values()
                .filter(|view| {
                    view.filter
                        .container_rules()
                        .iter()
                        .any(|reference| deleted.contains(&reference.container_id))
                })
                .map(|view| view.id)
                .collect(),
        })
    }

    pub fn remove_placement(
        &mut self,
        preview: &RemovalPreview,
        confirm_delete: bool,
    ) -> Result<(), String> {
        if &self.preview_removal(preview.id, preview.parent)? != preview {
            return Err(
                "The collection changed. Review the updated removal before trying again.".into(),
            );
        }
        if preview.action == RemovalAction::Delete && !confirm_delete {
            return Err("Confirm deletion before removing the last placement.".into());
        }
        self.transact(|document| {
            match preview.action {
                RemovalAction::Unlink => match preview.parent {
                    Some(parent) => document
                        .links
                        .retain(|link| !(link.parent == parent && link.child == preview.id)),
                    None => document.root_order.retain(|&id| id != preview.id),
                },
                RemovalAction::Delete => {
                    let deleted: BTreeSet<_> = preview.deleted_ids.iter().copied().collect();
                    document.deleted_item_ids.extend(deleted.iter().copied());
                    document.items.retain(|id, _| !deleted.contains(id));
                    document.links.retain(|link| {
                        !deleted.contains(&link.parent) && !deleted.contains(&link.child)
                    });
                    document.root_order.retain(|id| !deleted.contains(id));
                    for view in document.views.values_mut() {
                        view.preferences.retain(|id, _| !deleted.contains(id));
                    }
                }
            }
            Ok(())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{ContainerPreferences, Item, ItemKind, Link};

    fn add(doc: &mut Document, kind: ItemKind, parent: Option<i64>) -> i64 {
        doc.add_item(kind, "Same title".into(), parent).unwrap()
    }

    #[test]
    fn sole_tasks_and_folders_require_confirmation_and_never_reappear_as_roots() {
        for kind in [ItemKind::Task, ItemKind::Folder] {
            for nested in [false, true] {
                let mut doc = Document::new("delete".into());
                let parent = nested.then(|| add(&mut doc, ItemKind::Folder, None));
                let id = add(&mut doc, kind, parent);
                let preview = doc.preview_removal(id, parent).unwrap();
                let before = doc.clone();
                assert_eq!(preview.action, RemovalAction::Delete);
                assert!(doc.remove_placement(&preview, false).is_err());
                assert_eq!(doc, before);
                doc.remove_placement(&preview, true).unwrap();
                assert!(!doc.items.contains_key(&id));
                assert!(!doc.roots().contains(&id));
                assert_eq!(doc.revision, before.revision + 1);
                let new_id = add(&mut doc, kind, parent);
                assert!(new_id > id);
            }
        }
    }

    #[test]
    fn unlink_preserves_shared_attributes_children_selection_identity_and_order() {
        let mut doc = Document::new("unlink".into());
        let a = add(&mut doc, ItemKind::Folder, None);
        let b = add(&mut doc, ItemKind::Task, None);
        let first = add(&mut doc, ItemKind::Task, Some(a));
        let id = add(&mut doc, ItemKind::Folder, Some(a));
        let last = add(&mut doc, ItemKind::Task, Some(a));
        let child = add(&mut doc, ItemKind::Task, Some(id));
        doc.link(b, id).unwrap();
        let saved = doc.items.clone();
        let preview = doc.preview_removal(id, Some(a)).unwrap();
        assert_eq!(preview.action, RemovalAction::Unlink);
        assert!(preview.deleted_ids.is_empty());
        doc.remove_placement(&preview, false).unwrap();
        assert_eq!(doc.items, saved);
        assert_eq!(
            doc.links
                .iter()
                .filter(|l| l.parent == a)
                .map(|l| l.child)
                .collect::<Vec<_>>(),
            [first, last]
        );
        assert!(doc.links.contains(&Link { parent: id, child }));
        assert_eq!(doc.placements()[&id].parents, [b]);
        assert!(!doc.roots().contains(&id));
    }

    #[test]
    fn explicit_shared_root_counts_and_can_be_unlinked_in_either_direction() {
        for remove_root in [true, false] {
            let mut doc = Document::new("root".into());
            let a = add(&mut doc, ItemKind::Folder, None);
            let b = add(&mut doc, ItemKind::Folder, None);
            let id = add(&mut doc, ItemKind::Task, Some(a));
            doc.link(b, id).unwrap();
            doc.move_item(id, Some(a), None, None).unwrap();
            assert_eq!(doc.placements()[&id].count, 2);
            let parent = if remove_root { None } else { Some(b) };
            let preview = doc.preview_removal(id, parent).unwrap();
            doc.remove_placement(&preview, false).unwrap();
            assert_eq!(doc.placements()[&id].root, !remove_root);
            assert_eq!(doc.placements()[&id].count, 1);
            assert_eq!(
                doc.preview_removal(id, if remove_root { Some(b) } else { None })
                    .unwrap()
                    .action,
                RemovalAction::Delete
            );
        }
    }

    #[test]
    fn cascade_preserves_external_and_root_placements_and_shared_diamond_branches() {
        let mut doc = Document::new("cascade".into());
        let top = add(&mut doc, ItemKind::Folder, None);
        let outside = add(&mut doc, ItemKind::Folder, None);
        let a = add(&mut doc, ItemKind::Folder, Some(top));
        let b = add(&mut doc, ItemKind::Folder, Some(top));
        let diamond = add(&mut doc, ItemKind::Task, Some(a));
        doc.link(b, diamond).unwrap(); // both parents removed, so delete
        let kept = add(&mut doc, ItemKind::Folder, Some(a));
        doc.link(outside, kept).unwrap();
        let kept_child = add(&mut doc, ItemKind::Task, Some(kept));
        doc.link(b, kept_child).unwrap(); // surviving parent inside retained branch
        let rooted = add(&mut doc, ItemKind::Folder, Some(a));
        doc.root_order.push(rooted); // explicit root and parent
        let rooted_child = add(&mut doc, ItemKind::Task, Some(rooted));
        doc.set_container_preferences(1, a, ContainerPreferences::default())
            .unwrap();
        doc.set_container_preferences(1, kept, ContainerPreferences::default())
            .unwrap();
        let preview = doc.preview_removal(top, None).unwrap();
        assert_eq!(preview.deleted_ids, [top, a, b, diamond]);
        assert_eq!(preview.retained_child_ids, [kept, kept_child, rooted]);
        let next = doc.next_id;
        doc.remove_placement(&preview, true).unwrap();
        assert_eq!(
            doc.items.keys().copied().collect::<Vec<_>>(),
            [outside, kept, kept_child, rooted, rooted_child]
        );
        assert_eq!(doc.next_id, next);
        assert!(!doc.views[&1].preferences.contains_key(&a));
        assert!(doc.views[&1].preferences.contains_key(&kept));
        doc.validate().unwrap();
    }

    #[test]
    fn shared_parent_paths_do_not_create_extra_child_placements() {
        let mut doc = Document::new("paths".into());
        let a = add(&mut doc, ItemKind::Folder, None);
        let b = add(&mut doc, ItemKind::Folder, None);
        let folder = add(&mut doc, ItemKind::Folder, Some(a));
        doc.link(b, folder).unwrap();
        let child = add(&mut doc, ItemKind::Task, Some(folder));
        assert_eq!(doc.placements()[&child].count, 1);
        let preview = doc.preview_removal(child, Some(folder)).unwrap();
        assert_eq!(preview.action, RemovalAction::Delete);
        doc.remove_placement(&preview, true).unwrap();
        assert_eq!(doc.placements()[&folder].count, 2);
        assert!(!doc.items.contains_key(&child));
    }

    #[test]
    fn stale_altered_missing_and_exhausted_requests_leave_document_unchanged() {
        let mut doc = Document::new("stale".into());
        let a = add(&mut doc, ItemKind::Folder, None);
        let b = add(&mut doc, ItemKind::Folder, None);
        let id = add(&mut doc, ItemKind::Task, Some(a));
        doc.link(b, id).unwrap();
        let unlink = doc.preview_removal(id, Some(a)).unwrap();
        doc.unlink(b, id).unwrap();
        let before = doc.clone();
        assert!(doc.remove_placement(&unlink, false).is_err());
        assert_eq!(doc, before);
        let mut delete = doc.preview_removal(id, Some(a)).unwrap();
        delete.deleted_ids.push(b);
        assert!(doc.remove_placement(&delete, true).is_err());
        assert!(doc.preview_removal(id, Some(b)).is_err());
        assert!(doc.preview_removal(id, None).is_err());
        assert!(doc.preview_removal(-1, None).is_err());
        assert_eq!(doc, before);
        doc.revision = u64::MAX;
        let delete = doc.preview_removal(id, Some(a)).unwrap();
        let before = doc.clone();
        assert!(doc.remove_placement(&delete, true).is_err());
        assert_eq!(doc, before);
    }

    #[test]
    fn removing_unfinished_child_recomputes_automatic_ancestors() {
        let mut doc = Document::new("completion".into());
        let parent = add(&mut doc, ItemKind::Task, None);
        let done = add(&mut doc, ItemKind::Task, Some(parent));
        let pending = add(&mut doc, ItemKind::Task, Some(parent));
        doc.set_completed(done, true, false).unwrap();
        doc.set_auto_complete(parent, true).unwrap();
        assert!(!doc.items[&parent].completed);
        let preview = doc.preview_removal(pending, Some(parent)).unwrap();
        doc.remove_placement(&preview, true).unwrap();
        assert!(doc.items[&parent].completed);
    }

    #[test]
    fn very_deep_cascade_is_iterative_and_preserves_implicit_root_baseline() {
        let mut doc = Document::new("deep".into());
        // Imported schema-1 style roots need not be explicit in root_order.
        for id in 2..=10_001 {
            doc.items
                .insert(id, Item::new(id, ItemKind::Folder, "Folder".into()));
            if id > 2 {
                doc.links.push(Link {
                    parent: id - 1,
                    child: id,
                });
            }
        }
        doc.next_id = 10_002;
        let preview = doc.preview_removal(2, None).unwrap();
        assert_eq!(preview.deleted_ids.len(), 10_000);
        doc.remove_placement(&preview, true).unwrap();
        assert!(doc.items.is_empty());
        assert!(doc.roots().is_empty());
    }
}

#[cfg(test)]
mod view_tests {
    use super::*;
    use crate::{filter::FilterExpr, model::ItemKind};

    #[test]
    fn deleted_container_rules_retain_boolean_scope_and_report_nested_positions() {
        let mut doc = Document::new("rules".into());
        let folder = doc
            .add_item(ItemKind::Folder, "Deleted".into(), None)
            .unwrap();
        let task = doc.add_item(ItemKind::Task, "Keep".into(), None).unwrap();
        let membership = FilterExpr::Folder {
            folder_id: folder,
            recursive: true,
        };
        let filter = FilterExpr::Or {
            rules: vec![
                membership.clone(),
                FilterExpr::Not {
                    rule: Box::new(membership.clone()),
                },
            ],
        };
        let view = doc.add_view("Review me".into(), filter.clone()).unwrap();
        let preview = doc.preview_removal(folder, None).unwrap();
        assert_eq!(preview.affected_view_ids, [view]);
        doc.remove_placement(&preview, true).unwrap();
        assert_eq!(doc.views[&view].filter, filter);
        assert!(doc.deleted_item_ids.contains(&folder));
        let issues = filter.deleted_container_rules(&doc);
        assert_eq!(
            issues.iter().map(|r| r.path.as_str()).collect::<Vec<_>>(),
            ["1.1", "1.2.1"]
        );
        assert!(!membership.matches(&doc.items[&task], &doc));
        assert!(filter.matches(&doc.items[&task], &doc)); // NOT/OR semantics unchanged
        assert!(membership.creation_defaults(&doc).parent_ids.is_empty());
        assert!(!membership.creation_defaults(&doc).requirements.is_empty());
        doc.validate().unwrap();
        doc.edit_view(view, "Repaired".into(), FilterExpr::All)
            .unwrap();
        assert!(doc.views[&view]
            .filter
            .deleted_container_rules(&doc)
            .is_empty());
        assert!(FilterExpr::Folder {
            folder_id: 9999,
            recursive: true
        }
        .validate(&doc)
        .is_err());
        doc.deleted_item_ids.insert(task); // tombstones must never collide with live IDs
        assert!(doc.validate().is_err());
    }
}
