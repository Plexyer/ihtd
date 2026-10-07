//! Completion propagates through shared descendants and intervening folders.
//! Every pass is iterative, so hierarchy depth does not consume call-stack space.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

use crate::graph::{Graph, ItemId};
use crate::model::{item_id, Document, ItemKind};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CompletionInfo {
    pub effective_auto: bool,
    /// Highest independent enabled ancestors, excluding the task itself.
    pub enforcing_ancestor_ids: Vec<i64>,
    pub has_task_descendants: bool,
}

impl Document {
    pub fn completion_info(&self, id: i64) -> Result<CompletionInfo, String> {
        self.item(id)?;
        self.completion_states()?
            .remove(&id)
            .ok_or_else(|| format!("Item {id} does not exist"))
    }

    /// All item states in one graph pass; useful for rendering a large tree.
    pub fn completion_states(&self) -> Result<BTreeMap<i64, CompletionInfo>, String> {
        let graph = self.build_graph()?;
        let order = graph
            .topological_order()
            .map_err(|error| error.to_string())?;
        let mut result = inherited_states(self, &graph, &order)?;
        for &id in order.iter().rev() {
            let has_tasks = graph
                .children(id)
                .map_err(|error| error.to_string())?
                .iter()
                .any(|child| {
                    self.items[&child.get()].kind == ItemKind::Task
                        || result[&child.get()].has_task_descendants
                });
            result.get_mut(&id.get()).unwrap().has_task_descendants = has_tasks;
        }
        Ok(result)
    }

    /// Recompute derived completion after loading or changing relationships.
    /// Leaves leaf tasks manually controlled, even when inheritance is enabled.
    /// Does not change the revision; domain mutations call it before commit.
    pub fn recompute_completion(&mut self) -> Result<(), String> {
        let graph = self.build_graph()?;
        let order = graph
            .topological_order()
            .map_err(|error| error.to_string())?;
        let states = inherited_states(self, &graph, &order)?;
        // Each summary includes the current item, making a folder transparent.
        let mut summaries: BTreeMap<ItemId, (bool, bool)> = BTreeMap::new();
        for &id in order.iter().rev() {
            let mut has_descendant_tasks = false;
            let mut all_descendants_complete = true;
            for child in graph.children(id).map_err(|error| error.to_string())? {
                let (has_tasks, all_complete) = summaries[child];
                has_descendant_tasks |= has_tasks;
                all_descendants_complete &= all_complete;
            }
            let item = self.items.get_mut(&id.get()).unwrap();
            if item.kind == ItemKind::Task
                && states[&id.get()].effective_auto
                && has_descendant_tasks
            {
                item.completed = all_descendants_complete;
            }
            summaries.insert(
                id,
                (
                    has_descendant_tasks || item.kind == ItemKind::Task,
                    all_descendants_complete && (item.kind == ItemKind::Folder || item.completed),
                ),
            );
        }
        Ok(())
    }

    pub fn set_auto_complete(&mut self, id: i64, enabled: bool) -> Result<(), String> {
        self.transact(|document| {
            if document.item(id)?.kind != ItemKind::Task {
                return Err("Folders do not have automatic task completion".into());
            }
            let information = document.completion_info(id)?;
            if !enabled && !information.enforcing_ancestor_ids.is_empty() {
                let ids = information.enforcing_ancestor_ids.iter().map(i64::to_string).collect::<Vec<_>>().join(", ");
                return Err(format!("Automatic completion is required by ancestor task IDs: {ids}. Disable it on those tasks first."));
            }
            document.items.get_mut(&id).unwrap().auto_complete = enabled;
            Ok(())
        })
    }

    /// Confirming completion changes every descendant task's shared identity.
    /// An automatic parent can be reopened by reopening one of its subtasks.
    pub fn set_completed(
        &mut self,
        id: i64,
        completed: bool,
        confirm_descendants: bool,
    ) -> Result<(), String> {
        self.transact(|document| {
            if document.item(id)?.kind != ItemKind::Task {
                return Err("Folders are containers; use the view's folder hide toggle".into());
            }
            let information = document.completion_info(id)?;
            if !completed && information.effective_auto && information.has_task_descendants {
                return Err("This task's completion is automatic. Reopen a subtask or disable automatic completion on its enforcing ancestors.".into());
            }
            let graph = document.build_graph()?;
            let descendants = graph.descendants(item_id(id)?).map_err(|error| error.to_string())?;
            let unfinished: Vec<_> = descendants.into_iter().filter(|child| {
                let item = &document.items[&child.get()];
                item.kind == ItemKind::Task && !item.completed
            }).collect();
            if completed && !unfinished.is_empty() {
                if !confirm_descendants {
                    return Err(format!("CONFIRM_SUBTASKS: Complete this task and all {} unfinished descendant tasks? Shared tasks will complete in every placement.", unfinished.len()));
                }
                for child in unfinished {
                    document.items.get_mut(&child.get()).unwrap().completed = true;
                }
            }
            document.items.get_mut(&id).unwrap().completed = completed;
            Ok(())
        })
    }
}

fn inherited_states(
    document: &Document,
    graph: &Graph,
    order: &[ItemId],
) -> Result<BTreeMap<i64, CompletionInfo>, String> {
    let mut propagated: BTreeMap<ItemId, BTreeSet<i64>> = BTreeMap::new();
    let mut result = BTreeMap::new();
    for &id in order {
        let item = &document.items[&id.get()];
        let mut enforcing = BTreeSet::new();
        for parent in graph.parents(id).map_err(|error| error.to_string())? {
            enforcing.extend(propagated[&parent].iter().copied());
        }
        result.insert(
            id.get(),
            CompletionInfo {
                effective_auto: item.kind == ItemKind::Task
                    && (item.auto_complete || !enforcing.is_empty()),
                enforcing_ancestor_ids: enforcing.iter().copied().collect(),
                has_task_descendants: false,
            },
        );
        if enforcing.is_empty() && item.kind == ItemKind::Task && item.auto_complete {
            enforcing.insert(id.get());
        }
        propagated.insert(id, enforcing);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn task(document: &mut Document, title: &str, parent: Option<i64>) -> i64 {
        document
            .add_item(ItemKind::Task, title.into(), parent)
            .unwrap()
    }

    #[test]
    fn inheritance_crosses_folders_and_reports_highest_enforcer() {
        let mut document = Document::new("test".into());
        let holiday = task(&mut document, "Holiday", None);
        let documents = document
            .add_item(ItemKind::Folder, "Documents".into(), Some(holiday))
            .unwrap();
        let passport = task(&mut document, "Passport", Some(documents));
        let photo = task(&mut document, "Photo", Some(passport));
        document.set_auto_complete(passport, true).unwrap();
        document.set_auto_complete(holiday, true).unwrap();
        assert_eq!(
            document
                .completion_info(photo)
                .unwrap()
                .enforcing_ancestor_ids,
            [holiday]
        );
        assert!(document.completion_info(passport).unwrap().effective_auto);
        document.set_completed(photo, true, false).unwrap();
        assert!(document.items[&passport].completed);
        assert!(document.items[&holiday].completed);
        document.set_completed(photo, false, false).unwrap();
        assert!(!document.items[&passport].completed);
        assert!(!document.items[&holiday].completed);
        document.set_auto_complete(holiday, false).unwrap();
        assert_eq!(
            document
                .completion_info(photo)
                .unwrap()
                .enforcing_ancestor_ids,
            [passport]
        );
    }

    #[test]
    fn shared_child_requires_every_independent_enforcer_to_be_disabled() {
        let mut document = Document::new("test".into());
        let a = task(&mut document, "Project A", None);
        let b = task(&mut document, "Project B", None);
        let shared = task(&mut document, "Book travel", Some(a));
        let child = task(&mut document, "Buy ticket", Some(shared));
        document.link(b, shared).unwrap();
        document.set_auto_complete(a, true).unwrap();
        assert!(!document.completion_info(b).unwrap().effective_auto);
        assert!(document.completion_info(shared).unwrap().effective_auto);
        document.set_auto_complete(b, true).unwrap();
        assert_eq!(
            document
                .completion_info(shared)
                .unwrap()
                .enforcing_ancestor_ids,
            [a, b]
        );
        let before = document.clone();
        let error = document.set_auto_complete(shared, false).unwrap_err();
        assert!(error.contains(&format!("{a}, {b}")));
        assert_eq!(document, before);
        document.set_auto_complete(a, false).unwrap();
        assert!(document.set_auto_complete(shared, false).is_err());
        document.set_completed(child, true, false).unwrap();
        assert!(document.items[&b].completed);
        assert!(!document.items[&a].completed);
        document.set_auto_complete(b, false).unwrap();
        document.set_auto_complete(shared, false).unwrap();
        assert!(!document.completion_info(shared).unwrap().effective_auto);
    }

    #[test]
    fn completing_branch_requires_confirmation_and_updates_shared_descendants() {
        let mut document = Document::new("test".into());
        let a = task(&mut document, "A", None);
        let b = task(&mut document, "B", None);
        let shared = task(&mut document, "Shared", Some(a));
        let child = task(&mut document, "Child", Some(shared));
        document.link(b, shared).unwrap();
        document.set_auto_complete(b, true).unwrap();
        let before = document.clone();
        assert!(document
            .set_completed(a, true, false)
            .unwrap_err()
            .starts_with("CONFIRM_SUBTASKS:"));
        assert_eq!(document, before);
        document.set_completed(a, true, true).unwrap();
        for id in [a, b, shared, child] {
            assert!(document.items[&id].completed);
        }
        assert!(document.set_completed(b, false, false).is_err());
    }

    #[test]
    fn new_child_at_any_depth_reopens_all_shared_automatic_ancestors() {
        let mut document = Document::new("test".into());
        let a = task(&mut document, "A", None);
        let b = task(&mut document, "B", None);
        let shared = task(&mut document, "Shared", Some(a));
        document.link(b, shared).unwrap();
        document.set_auto_complete(a, true).unwrap();
        document.set_auto_complete(b, true).unwrap();
        document.set_completed(shared, true, false).unwrap();
        for id in [a, b, shared] {
            assert!(document.items[&id].completed);
        }
        let folder = document
            .add_item(ItemKind::Folder, "Folder".into(), Some(shared))
            .unwrap();
        assert!(document.items[&a].completed);
        let leaf = task(&mut document, "New task", Some(folder));
        for id in [a, b, shared, leaf] {
            assert!(!document.items[&id].completed);
        }
        document.set_completed(leaf, true, false).unwrap();
        for id in [a, b, shared, leaf] {
            assert!(document.items[&id].completed);
        }
    }

    #[test]
    fn leaf_tasks_do_not_complete_vacuously_and_converting_to_folder_drops_task_state() {
        let mut document = Document::new("test".into());
        let leaf = task(&mut document, "Leaf", None);
        document.set_auto_complete(leaf, true).unwrap();
        assert!(!document.items[&leaf].completed);
        document.set_completed(leaf, true, false).unwrap();
        document.convert_kind(leaf, ItemKind::Folder).unwrap();
        assert!(!document.items[&leaf].completed);
        assert!(!document.items[&leaf].auto_complete);
        document.convert_kind(leaf, ItemKind::Task).unwrap();
        assert!(!document.items[&leaf].completed);
    }
}
