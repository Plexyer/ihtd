//! Serializable document state and atomic mutations shared by every platform.

use std::collections::{BTreeMap, BTreeSet};

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

use crate::filter::FilterExpr;
pub use crate::graph::ItemKind;
use crate::graph::{Graph, ItemId};

pub const SCHEMA_VERSION: u32 = 2;

#[cfg(test)]
mod move_tests {
    use super::*;
    #[test]
    fn moves_keep_shared_identity_children_and_other_placements() {
        let mut doc = Document::new("moves".into());
        let a = doc.add_item(ItemKind::Folder, "A".into(), None).unwrap();
        let b = doc.add_item(ItemKind::Task, "B".into(), None).unwrap();
        let c = doc.add_item(ItemKind::Folder, "C".into(), None).unwrap();
        let task = doc
            .add_item(ItemKind::Task, "Shared".into(), Some(a))
            .unwrap();
        let child = doc
            .add_item(ItemKind::Task, "Child".into(), Some(task))
            .unwrap();
        doc.link(b, task).unwrap();
        doc.move_item(task, Some(a), Some(c), None).unwrap();
        assert!(!doc.links.contains(&Link {
            parent: a,
            child: task
        }));
        assert!(doc.links.contains(&Link {
            parent: b,
            child: task
        }));
        assert!(doc.links.contains(&Link {
            parent: c,
            child: task
        }));
        assert!(doc.links.contains(&Link {
            parent: task,
            child
        }));
        doc.move_item(task, Some(c), None, Some(a)).unwrap();
        assert_eq!(doc.roots().first(), Some(&task));
        assert!(doc.links.contains(&Link {
            parent: b,
            child: task
        }));
        doc.move_item(task, None, Some(a), None).unwrap();
        assert!(!doc.roots().contains(&task));
        doc.move_item(task, Some(a), Some(b), None).unwrap();
        assert_eq!(doc.links.iter().filter(|l| l.child == task).count(), 1);
        assert_eq!(doc.items.len(), 5);
    }

    #[test]
    fn moves_reorder_and_reject_cycles_or_stale_sources_atomically() {
        let mut doc = Document::new("moves".into());
        let a = doc.add_item(ItemKind::Folder, "A".into(), None).unwrap();
        let b = doc.add_item(ItemKind::Task, "B".into(), Some(a)).unwrap();
        let c = doc.add_item(ItemKind::Task, "C".into(), Some(a)).unwrap();
        doc.move_item(c, Some(a), Some(a), Some(b)).unwrap();
        assert_eq!(
            doc.links
                .iter()
                .filter(|l| l.parent == a)
                .map(|l| l.child)
                .collect::<Vec<_>>(),
            [c, b]
        );
        let saved = doc.clone();
        assert!(doc.move_item(a, None, Some(b), None).is_err());
        assert!(doc.move_item(b, None, None, None).is_err());
        assert!(doc.move_item(c, Some(a), Some(a), Some(c)).is_err());
        assert_eq!(doc, saved);
    }

    #[test]
    fn moving_an_unfinished_task_reopens_automatic_destination() {
        let mut doc = Document::new("moves".into());
        let a = doc.add_item(ItemKind::Task, "Auto".into(), None).unwrap();
        let done = doc
            .add_item(ItemKind::Task, "Done".into(), Some(a))
            .unwrap();
        doc.set_completed(done, true, false).unwrap();
        doc.set_auto_complete(a, true).unwrap();
        assert!(doc.items[&a].completed);
        let task = doc.add_item(ItemKind::Task, "New".into(), None).unwrap();
        doc.move_item(task, None, Some(a), None).unwrap();
        assert!(!doc.items[&a].completed);
        doc.move_item(task, Some(a), None, None).unwrap();
        assert!(doc.items[&a].completed);
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Item {
    pub id: i64,
    pub kind: ItemKind,
    pub title: String,
    pub notes: String,
    pub due_date: Option<String>,
    pub priority: u8,
    pub completed: bool,
    /// The local preference; inherited automatic completion is derived.
    pub auto_complete: bool,
    #[serde(default)]
    pub tag_ids: Vec<i64>,
}

impl Item {
    pub fn new(id: i64, kind: ItemKind, title: String) -> Self {
        Self {
            id,
            kind,
            title,
            notes: String::new(),
            due_date: None,
            priority: 0,
            completed: false,
            auto_complete: false,
            tag_ids: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Link {
    pub parent: i64,
    pub child: i64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Tag {
    pub id: i64,
    pub name: String,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(default)]
pub struct ContainerPreferences {
    /// None uses the nearest inherited setting, or true when none applies.
    pub hide_completed: Option<bool>,
    pub inherit_hide_completed: bool,
    pub folder_hidden: bool,
    pub reappear_on_new: bool,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct View {
    pub id: i64,
    pub name: String,
    pub filter: FilterExpr,
    #[serde(default)]
    pub preferences: BTreeMap<i64, ContainerPreferences>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Document {
    pub schema_version: u32,
    pub document_id: String,
    pub revision: u64,
    pub next_id: i64,
    pub items: BTreeMap<i64, Item>,
    pub links: Vec<Link>,
    /// Ordered explicit root placements, including shared items with parents.
    #[serde(default)]
    pub root_order: Vec<i64>,
    pub tags: BTreeMap<i64, Tag>,
    pub views: BTreeMap<i64, View>,
}

impl Document {
    pub fn new(document_id: String) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            document_id,
            revision: 0,
            next_id: 2,
            items: BTreeMap::new(),
            links: Vec::new(),
            root_order: Vec::new(),
            tags: BTreeMap::new(),
            views: BTreeMap::from([(
                1,
                View {
                    id: 1,
                    name: "All tasks".into(),
                    filter: FilterExpr::All,
                    preferences: BTreeMap::new(),
                },
            )]),
        }
    }

    /// Validate data from disk before it can replace the open document.
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "Unsupported document schema {}",
                self.schema_version
            ));
        }
        if self.document_id.trim().is_empty() {
            return Err("Document ID must not be empty".into());
        }
        let mut ids = BTreeSet::new();
        for (&key, item) in &self.items {
            validate_id(&mut ids, key, item.id)?;
            validate_name(&item.title, "Item title")?;
            if item.priority > 3 {
                return Err(format!(
                    "Item {} has invalid priority {}",
                    item.id, item.priority
                ));
            }
            if let Some(date) = &item.due_date {
                let parsed = NaiveDate::parse_from_str(date, "%Y-%m-%d")
                    .map_err(|_| format!("Item {} has an invalid due date", item.id))?;
                if parsed.format("%Y-%m-%d").to_string() != *date {
                    return Err(format!("Item {} due date must use YYYY-MM-DD", item.id));
                }
            }
            if item.kind == ItemKind::Folder && (item.completed || item.auto_complete) {
                return Err(format!(
                    "Folder {} cannot have task completion state",
                    item.id
                ));
            }
            let mut tags = BTreeSet::new();
            for tag_id in &item.tag_ids {
                if !self.tags.contains_key(tag_id) || !tags.insert(tag_id) {
                    return Err(format!(
                        "Item {} has a missing or duplicate tag {}",
                        item.id, tag_id
                    ));
                }
            }
        }
        for (&key, tag) in &self.tags {
            validate_id(&mut ids, key, tag.id)?;
            validate_name(&tag.name, "Tag name")?;
        }
        for (&key, view) in &self.views {
            validate_id(&mut ids, key, view.id)?;
            validate_name(&view.name, "View name")?;
            view.filter.validate(self)?;
            for &item_id in view.preferences.keys() {
                self.item(item_id)?;
            }
        }
        if self.next_id <= ids.last().copied().unwrap_or(0) || self.next_id <= 0 {
            return Err("Next ID must be positive and greater than every allocated ID".into());
        }
        self.build_graph()?;
        let mut roots = BTreeSet::new();
        for &id in &self.root_order {
            self.item(id)?;
            if !roots.insert(id) {
                return Err("Duplicate root placement".into());
            }
        }
        Ok(())
    }

    pub fn roots(&self) -> Vec<i64> {
        let placed: BTreeSet<_> = self.links.iter().map(|l| l.child).collect();
        let explicit: BTreeSet<_> = self.root_order.iter().copied().collect();
        let mut roots = self.root_order.clone();
        roots.extend(
            self.items
                .keys()
                .filter(|id| !placed.contains(id) && !explicit.contains(id))
                .copied(),
        );
        roots
    }

    /// Move one parent/child relationship (or root placement), never the item.
    pub fn move_item(
        &mut self,
        id: i64,
        source: Option<i64>,
        destination: Option<i64>,
        before: Option<i64>,
    ) -> Result<(), String> {
        self.transact(|document| {
            document.item(id)?;
            let mut roots = document.roots();
            if let Some(parent) = source {
                if !document
                    .links
                    .iter()
                    .any(|l| l.parent == parent && l.child == id)
                {
                    return Err("The dragged placement no longer exists".into());
                }
            } else if !roots.contains(&id) {
                return Err("The dragged top-level placement no longer exists".into());
            }
            if destination == Some(id) || before == Some(id) {
                return Err("Cannot move an item onto itself".into());
            }
            if let Some(parent) = destination {
                document.item(parent)?;
                if document
                    .build_graph()?
                    .descendants(item_id(id)?)
                    .map_err(|e| e.to_string())?
                    .contains(&item_id(parent)?)
                {
                    return Err("Cannot move an item into one of its descendants".into());
                }
            }
            if let Some(sibling) = before {
                let exists = match destination {
                    Some(parent) => document
                        .links
                        .iter()
                        .any(|l| l.parent == parent && l.child == sibling),
                    None => roots.contains(&sibling),
                };
                if !exists {
                    return Err("The target position no longer exists".into());
                }
            }
            if let Some(parent) = source {
                document
                    .links
                    .retain(|l| !(l.parent == parent && l.child == id));
            } else {
                roots.retain(|&root| root != id);
            }
            if let Some(parent) = destination {
                // Moving onto an existing placement coalesces the two links.
                document
                    .links
                    .retain(|l| !(l.parent == parent && l.child == id));
                let index = before
                    .and_then(|sibling| {
                        document
                            .links
                            .iter()
                            .position(|l| l.parent == parent && l.child == sibling)
                    })
                    .unwrap_or(document.links.len());
                document.links.insert(index, Link { parent, child: id });
            } else {
                roots.retain(|&root| root != id);
                let index = before
                    .and_then(|sibling| roots.iter().position(|&root| root == sibling))
                    .unwrap_or(roots.len());
                roots.insert(index, id);
            }
            document.root_order = roots;
            if source != destination {
                document.reveal_new_tasks(id)?;
            }
            Ok(())
        })
    }

    pub fn build_graph(&self) -> Result<Graph, String> {
        let items = self
            .items
            .values()
            .map(|item| {
                Ok((
                    ItemId::new(item.id).map_err(|error| error.to_string())?,
                    item.kind,
                ))
            })
            .collect::<Result<Vec<_>, String>>()?;
        let links = self
            .links
            .iter()
            .map(|link| {
                Ok((
                    ItemId::new(link.parent).map_err(|error| error.to_string())?,
                    ItemId::new(link.child).map_err(|error| error.to_string())?,
                ))
            })
            .collect::<Result<Vec<_>, String>>()?;
        Graph::from_parts(items, links).map_err(|error| error.to_string())
    }

    pub fn item(&self, id: i64) -> Result<&Item, String> {
        self.items
            .get(&id)
            .ok_or_else(|| format!("Item {id} does not exist"))
    }

    pub fn add_item(
        &mut self,
        kind: ItemKind,
        title: String,
        parent: Option<i64>,
    ) -> Result<i64, String> {
        self.transact(|document| {
            validate_name(&title, "Item title")?;
            if let Some(parent) = parent {
                document.item(parent)?;
            }
            let id = document.allocate_id()?;
            document.items.insert(id, Item::new(id, kind, title));
            if let Some(parent) = parent {
                document.links.push(Link { parent, child: id });
            }
            if kind == ItemKind::Task {
                document.reveal_new_tasks(id)?;
            }
            Ok(id)
        })
    }

    /// Metadata edits do not bypass completion and conversion commands.
    pub fn edit_item(
        &mut self,
        id: i64,
        title: String,
        notes: String,
        due_date: Option<String>,
        priority: u8,
        mut tag_ids: Vec<i64>,
    ) -> Result<(), String> {
        self.transact(|document| {
            let item = document
                .items
                .get_mut(&id)
                .ok_or_else(|| format!("Item {id} does not exist"))?;
            tag_ids.sort_unstable();
            tag_ids.dedup();
            item.title = title;
            item.notes = notes;
            item.due_date = due_date;
            item.priority = priority;
            item.tag_ids = tag_ids;
            Ok(())
        })
    }

    pub fn link(&mut self, parent: i64, child: i64) -> Result<(), String> {
        self.transact(|document| {
            if !document.links.iter().any(|l| l.child == child) {
                document.root_order.retain(|&id| id != child);
            }
            document
                .build_graph()?
                .link(item_id(parent)?, item_id(child)?)
                .map_err(|error| error.to_string())?;
            document.links.push(Link { parent, child });
            document.reveal_new_tasks(child)?;
            Ok(())
        })
    }

    /// Removing a placement keeps the item and all other placements intact.
    pub fn unlink(&mut self, parent: i64, child: i64) -> Result<(), String> {
        self.transact(|document| {
            let index = document
                .links
                .iter()
                .position(|link| link.parent == parent && link.child == child)
                .ok_or_else(|| format!("Item {child} is not a child of item {parent}"))?;
            document.links.remove(index);
            Ok(())
        })
    }

    pub fn convert_kind(&mut self, id: i64, kind: ItemKind) -> Result<(), String> {
        self.transact(|document| {
            let item = document
                .items
                .get_mut(&id)
                .ok_or_else(|| format!("Item {id} does not exist"))?;
            item.kind = kind;
            if kind == ItemKind::Folder {
                item.completed = false;
                item.auto_complete = false;
            } else {
                for view in document.views.values_mut() {
                    if let Some(preferences) = view.preferences.get_mut(&id) {
                        preferences.folder_hidden = false;
                    }
                }
                document.reveal_new_tasks(id)?;
            }
            Ok(())
        })
    }

    pub fn add_tag(&mut self, name: String) -> Result<i64, String> {
        self.transact(|document| {
            validate_name(&name, "Tag name")?;
            let id = document.allocate_id()?;
            document.tags.insert(id, Tag { id, name });
            Ok(id)
        })
    }

    pub fn rename_tag(&mut self, id: i64, name: String) -> Result<(), String> {
        self.transact(|document| {
            document
                .tags
                .get_mut(&id)
                .ok_or_else(|| format!("Tag {id} does not exist"))?
                .name = name;
            Ok(())
        })
    }

    /// A tag referenced by a view cannot be removed until that filter changes.
    pub fn remove_tag(&mut self, id: i64) -> Result<(), String> {
        self.transact(|document| {
            document
                .tags
                .remove(&id)
                .ok_or_else(|| format!("Tag {id} does not exist"))?;
            for item in document.items.values_mut() {
                item.tag_ids.retain(|&tag| tag != id);
            }
            Ok(())
        })
    }

    pub fn add_view(&mut self, name: String, filter: FilterExpr) -> Result<i64, String> {
        self.transact(|document| {
            let id = document.allocate_id()?;
            document.views.insert(
                id,
                View {
                    id,
                    name,
                    filter,
                    preferences: BTreeMap::new(),
                },
            );
            Ok(id)
        })
    }

    pub fn edit_view(&mut self, id: i64, name: String, filter: FilterExpr) -> Result<(), String> {
        self.transact(|document| {
            let view = document
                .views
                .get_mut(&id)
                .ok_or_else(|| format!("View {id} does not exist"))?;
            view.name = name;
            view.filter = filter;
            Ok(())
        })
    }

    pub fn remove_view(&mut self, id: i64) -> Result<(), String> {
        self.transact(|document| {
            if document.views.len() <= 1 {
                return Err("Keep at least one view".into());
            }
            document
                .views
                .remove(&id)
                .ok_or_else(|| format!("View {id} does not exist"))?;
            Ok(())
        })
    }

    pub fn set_container_preferences(
        &mut self,
        view_id: i64,
        item_id: i64,
        preferences: ContainerPreferences,
    ) -> Result<(), String> {
        self.transact(|document| {
            let item = document.item(item_id)?;
            if item.kind != ItemKind::Folder && preferences.folder_hidden {
                return Err("Only folders can use the folder hide toggle".into());
            }
            document
                .views
                .get_mut(&view_id)
                .ok_or_else(|| format!("View {view_id} does not exist"))?
                .preferences
                .insert(item_id, preferences);
            Ok(())
        })
    }

    /// Resolve visibility for this placement path, allowing explicit overrides.
    /// The path includes the container whose children are being rendered.
    pub fn hide_completed_for_path(&self, view_id: i64, path: &[i64]) -> Result<bool, String> {
        let view = self
            .views
            .get(&view_id)
            .ok_or_else(|| format!("View {view_id} does not exist"))?;
        let mut inherited = true;
        let mut resolved = true;
        for (index, &id) in path.iter().enumerate() {
            self.item(id)?;
            if index > 0
                && !self
                    .links
                    .iter()
                    .any(|link| link.parent == path[index - 1] && link.child == id)
            {
                return Err("Visibility path contains an invalid placement".into());
            }
            let preferences = view.preferences.get(&id).cloned().unwrap_or_default();
            resolved = preferences.hide_completed.unwrap_or(inherited);
            if preferences.inherit_hide_completed {
                inherited = resolved;
            }
        }
        Ok(resolved)
    }

    pub(crate) fn transact<T>(
        &mut self,
        operation: impl FnOnce(&mut Self) -> Result<T, String>,
    ) -> Result<T, String> {
        let mut candidate = self.clone();
        let result = operation(&mut candidate)?;
        candidate.validate()?;
        candidate.recompute_completion()?;
        candidate.revision = self
            .revision
            .checked_add(1)
            .ok_or("Document revision exhausted")?;
        *self = candidate;
        Ok(result)
    }

    fn allocate_id(&mut self) -> Result<i64, String> {
        let id = self.next_id;
        self.next_id = id.checked_add(1).ok_or("Document ID space exhausted")?;
        Ok(id)
    }

    fn reveal_new_tasks(&mut self, id: i64) -> Result<(), String> {
        let graph = self.build_graph()?;
        let node = item_id(id)?;
        let contains_task = self.item(id)?.kind == ItemKind::Task
            || graph
                .descendants(node)
                .map_err(|error| error.to_string())?
                .into_iter()
                .any(|child| self.items[&child.get()].kind == ItemKind::Task);
        if !contains_task {
            return Ok(());
        }
        let ancestors = graph.ancestors(node).map_err(|error| error.to_string())?;
        for view in self.views.values_mut() {
            for ancestor in &ancestors {
                if let Some(preferences) = view.preferences.get_mut(&ancestor.get()) {
                    if preferences.reappear_on_new {
                        preferences.folder_hidden = false;
                    }
                }
            }
        }
        Ok(())
    }
}

pub(crate) fn item_id(value: i64) -> Result<ItemId, String> {
    ItemId::new(value).map_err(|error| error.to_string())
}

fn validate_id(ids: &mut BTreeSet<i64>, key: i64, id: i64) -> Result<(), String> {
    if id <= 0 || key != id || !ids.insert(id) {
        Err(format!(
            "ID {id} must be positive, globally unique, and match its map key"
        ))
    } else {
        Ok(())
    }
}

fn validate_name(name: &str, label: &str) -> Result<(), String> {
    if name.trim().is_empty() {
        Err(format!("{label} must not be empty"))
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn item_identity_is_independent_of_title_and_shared_with_tags_and_views() {
        let mut document = Document::new("test".into());
        let first = document
            .add_item(ItemKind::Task, "Same title".into(), None)
            .unwrap();
        let second = document
            .add_item(ItemKind::Task, "Same title".into(), None)
            .unwrap();
        let tag = document.add_tag("Work".into()).unwrap();
        let view = document.add_view("Other".into(), FilterExpr::All).unwrap();
        assert_eq!([first, second, tag, view], [2, 3, 4, 5]);
        let encoded = serde_json::to_string(&document).unwrap();
        let decoded: Document = serde_json::from_str(&encoded).unwrap();
        decoded.validate().unwrap();
        assert_eq!(decoded, document);
    }

    #[test]
    fn imported_cycles_and_id_collisions_are_rejected() {
        let mut document = Document::new("test".into());
        let a = document.add_item(ItemKind::Task, "A".into(), None).unwrap();
        let b = document
            .add_item(ItemKind::Task, "B".into(), Some(a))
            .unwrap();
        let before = document.clone();
        assert!(document.link(b, a).is_err());
        assert_eq!(document, before);
        document.links.push(Link {
            parent: b,
            child: a,
        });
        assert!(document.validate().is_err());
        document = before;
        document.tags.insert(
            a,
            Tag {
                id: a,
                name: "Invalid".into(),
            },
        );
        assert!(document.validate().is_err());
    }

    #[test]
    fn invalid_metadata_edits_are_atomic() {
        let mut document = Document::new("test".into());
        let task = document
            .add_item(ItemKind::Task, "Task".into(), None)
            .unwrap();
        let before = document.clone();
        assert!(document
            .edit_item(
                task,
                "Changed".into(),
                String::new(),
                Some("2026-02-30".into()),
                1,
                vec![]
            )
            .is_err());
        assert!(document
            .edit_item(task, "Changed".into(), String::new(), None, 4, vec![])
            .is_err());
        assert_eq!(document, before);
    }

    #[test]
    fn visibility_inheritance_is_optional_overridable_and_per_view() {
        let mut document = Document::new("test".into());
        let a = document
            .add_item(ItemKind::Folder, "A".into(), None)
            .unwrap();
        let b = document
            .add_item(ItemKind::Task, "B".into(), Some(a))
            .unwrap();
        let c = document
            .add_item(ItemKind::Task, "C".into(), Some(b))
            .unwrap();
        let other = document.add_view("Other".into(), FilterExpr::All).unwrap();
        document
            .set_container_preferences(
                1,
                a,
                ContainerPreferences {
                    hide_completed: Some(false),
                    inherit_hide_completed: true,
                    ..Default::default()
                },
            )
            .unwrap();
        assert!(!document.hide_completed_for_path(1, &[a, b, c]).unwrap());
        assert!(document.hide_completed_for_path(other, &[a, b, c]).unwrap());
        document
            .set_container_preferences(
                1,
                b,
                ContainerPreferences {
                    hide_completed: Some(true),
                    ..Default::default()
                },
            )
            .unwrap();
        assert!(document.hide_completed_for_path(1, &[a, b]).unwrap());
        assert!(!document.hide_completed_for_path(1, &[a, b, c]).unwrap());
    }

    #[test]
    fn hidden_folder_reappears_only_when_configured_and_new_task_is_added_below() {
        let mut document = Document::new("test".into());
        let folder = document
            .add_item(ItemKind::Folder, "PC".into(), None)
            .unwrap();
        let other = document.add_view("Other".into(), FilterExpr::All).unwrap();
        for view_id in [1, other] {
            document
                .set_container_preferences(
                    view_id,
                    folder,
                    ContainerPreferences {
                        folder_hidden: true,
                        reappear_on_new: view_id == 1,
                        ..Default::default()
                    },
                )
                .unwrap();
        }
        let nested = document
            .add_item(ItemKind::Folder, "Parts".into(), Some(folder))
            .unwrap();
        assert!(document.views[&1].preferences[&folder].folder_hidden);
        document
            .add_item(ItemKind::Task, "Buy GPU".into(), Some(nested))
            .unwrap();
        assert!(!document.views[&1].preferences[&folder].folder_hidden);
        assert!(document.views[&other].preferences[&folder].folder_hidden);
    }
}
