//! Appearance-aware actions and finite-snapshot copy operations.
use crate::model::{Document, Link};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, VecDeque};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ItemAction {
    Unlink,
    Delete,
}
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct ActionPreview {
    pub document_id: String,
    pub revision: u64,
    pub id: i64,
    pub path: Vec<i64>,
    pub action: ItemAction,
    pub blocking_parent: Option<i64>,
    pub deleted_ids: Vec<i64>,
    pub retained_child_ids: Vec<i64>,
    pub affected_view_ids: Vec<i64>,
    pub appearances: String,
}
fn add_decimal(a: &str, b: &str) -> String {
    let mut out = Vec::new();
    let mut carry = 0;
    let mut a = a.bytes().rev();
    let mut b = b.bytes().rev();
    loop {
        let (x, y) = (a.next(), b.next());
        if x.is_none() && y.is_none() && carry == 0 {
            break;
        }
        let n = x.map(|v| v - b'0').unwrap_or(0) + y.map(|v| v - b'0').unwrap_or(0) + carry;
        out.push(b'0' + n % 10);
        carry = n / 10;
    }
    out.reverse();
    String::from_utf8(out).unwrap()
}
fn adjacency(doc: &Document) -> BTreeMap<i64, Vec<i64>> {
    let mut result: BTreeMap<i64, Vec<i64>> = BTreeMap::new();
    for edge in &doc.links {
        result.entry(edge.parent).or_default().push(edge.child);
    }
    result
}
fn topo(doc: &Document) -> Vec<i64> {
    let children = adjacency(doc);
    let mut degrees: BTreeMap<_, usize> = doc.items.keys().map(|&id| (id, 0)).collect();
    for l in &doc.links {
        *degrees.get_mut(&l.child).unwrap() += 1;
    }
    let mut queue: VecDeque<_> = degrees
        .iter()
        .filter(|(_, n)| **n == 0)
        .map(|(&id, _)| id)
        .collect();
    let mut result = Vec::new();
    while let Some(id) = queue.pop_front() {
        result.push(id);
        for child in children.get(&id).into_iter().flatten() {
            let degree = degrees.get_mut(child).unwrap();
            *degree -= 1;
            if *degree == 0 {
                queue.push_back(*child);
            }
        }
    }
    result
}
struct Copied {
    root: i64,
    edges: BTreeMap<(i64, i64), i64>,
}
fn clone_node(source: &Document, target: &mut Document, id: i64) -> Result<i64, String> {
    let new = target.allocate_id()?;
    let mut item = source
        .items
        .get(&id)
        .ok_or("Source no longer exists")?
        .clone();
    item.id = new;
    target.items.insert(new, item);
    if let Some(p) = source.parent_indicator_defaults.get(&id) {
        target.parent_indicator_defaults.insert(new, p.clone());
    }
    for (&view, saved) in &source.views {
        if let Some(pref) = saved.preferences.get(&id) {
            target
                .views
                .get_mut(&view)
                .unwrap()
                .preferences
                .insert(new, pref.clone());
        }
    }
    Ok(new)
}
// Bound independent expansion of highly shared DAGs; never partially apply it.
const COPY_LIMIT: usize = 100_000;
fn copy_branch(
    source: &Document,
    target: &mut Document,
    root: i64,
    depth: Option<u32>,
    independent: bool,
) -> Result<Copied, String> {
    let children = adjacency(source);
    let mut edges = BTreeMap::new();
    let mut depths = BTreeMap::from([(root, 0u32)]);
    let mut queue = VecDeque::from([root]);
    while let Some(id) = queue.pop_front() {
        let d = depths[&id];
        for &child in children.get(&id).into_iter().flatten() {
            if let std::collections::btree_map::Entry::Vacant(e) = depths.entry(child) {
                e.insert(d + 1);
                queue.push_back(child);
            }
        }
    }
    let copied_root;
    if !independent {
        let mut ids = BTreeMap::new();
        for (&id, &d) in &depths {
            if depth.is_none_or(|limit| d <= limit) {
                if ids.len() >= COPY_LIMIT {
                    return Err("This copy is too large. Choose a smaller copy depth.".into());
                }
                ids.insert(id, clone_node(source, target, id)?);
            }
        }
        copied_root = ids[&root];
        for (&old, &new) in &ids {
            for &child in children.get(&old).into_iter().flatten() {
                let child_id = ids.get(&child).copied().unwrap_or(child);
                target.links.push(Link {
                    parent: new,
                    child: child_id,
                });
                edges.insert((new, child), child_id);
            }
        }
    } else {
        copied_root = clone_node(source, target, root)?;
        let mut stack = vec![(root, copied_root, 0u32)];
        let mut count = 1;
        while let Some((old, new, d)) = stack.pop() {
            for &child in children.get(&old).into_iter().flatten() {
                let child_id = if depth.is_none_or(|limit| d < limit) {
                    if count >= COPY_LIMIT {
                        return Err("This independent copy is too large. Reduce depth or preserve internal links.".into());
                    }
                    count += 1;
                    let id = clone_node(source, target, child)?;
                    stack.push((child, id, d + 1));
                    id
                } else {
                    child
                };
                target.links.push(Link {
                    parent: new,
                    child: child_id,
                });
                edges.insert((new, child), child_id);
            }
        }
    }
    Ok(Copied {
        root: copied_root,
        edges,
    })
}
fn prune(doc: &mut Document, deleted: &BTreeSet<i64>) {
    doc.deleted_item_ids.extend(deleted);
    doc.items.retain(|id, _| !deleted.contains(id));
    doc.links
        .retain(|l| !deleted.contains(&l.parent) && !deleted.contains(&l.child));
    doc.root_order.retain(|id| !deleted.contains(id));
    doc.parent_indicator_defaults
        .retain(|id, _| !deleted.contains(id));
    for view in doc.views.values_mut() {
        view.preferences.retain(|id, _| !deleted.contains(id));
    }
}
impl Document {
    /// Exact decimal counts avoid overflow without enumerating hierarchy paths.
    pub fn appearance_counts(&self) -> BTreeMap<i64, String> {
        let children = adjacency(self);
        let mut result: BTreeMap<_, _> =
            self.items.keys().map(|&id| (id, "0".to_string())).collect();
        for id in self.roots() {
            result.insert(id, "1".into());
        }
        for id in topo(self) {
            for child in children.get(&id).into_iter().flatten() {
                result.insert(*child, add_decimal(&result[child], &result[&id]));
            }
        }
        result
    }
    pub fn copy_options(&self, id: i64) -> Result<(Vec<i64>, u32), String> {
        if !self.items.contains_key(&id) {
            return Err("Source no longer exists.".into());
        }
        let children = adjacency(self);
        let mut depths = BTreeMap::from([(id, 0u32)]);
        for node in topo(self) {
            if let Some(d) = depths.get(&node).copied() {
                for &child in children.get(&node).into_iter().flatten() {
                    let old = depths.entry(child).or_default();
                    *old = (*old).max(d + 1);
                }
            }
        }
        Ok((
            depths.keys().copied().filter(|v| *v != id).collect(),
            depths.values().copied().max().unwrap_or(0),
        ))
    }
    pub fn link_or_copy(
        &mut self,
        source: i64,
        destination: Option<i64>,
        copying: bool,
        depth: Option<u32>,
        independent: bool,
        revision: u64,
    ) -> Result<i64, String> {
        if self.revision != revision {
            return Err("The collection changed. Reopen Link / copy to review it.".into());
        }
        let (descendants, _) = self.copy_options(source)?;
        let circular = destination.is_some_and(|d| d == source || descendants.contains(&d));
        if circular && (!copying || depth.is_some()) {
            return Err("Copying into this source or a child requires copying all descendants. Linking here would create a cycle.".into());
        }
        if destination.is_some_and(|id| !self.items.contains_key(&id)) {
            return Err("Destination no longer exists.".into());
        }
        let snapshot = self.clone();
        self.transact(|doc| {
            // Freeze implicit roots before adding incoming links to existing nodes.
            doc.root_order = doc.roots();
            let id = if copying {
                copy_branch(&snapshot, doc, source, depth, independent)?.root
            } else {
                source
            };
            match destination {
                Some(parent) => {
                    if doc
                        .links
                        .iter()
                        .any(|l| l.parent == parent && l.child == id)
                    {
                        return Err("This item is already linked there.".into());
                    }
                    doc.links.push(Link { parent, child: id });
                }
                None => {
                    if doc.root_order.contains(&id) {
                        return Err("This item is already at top level.".into());
                    }
                    doc.root_order.push(id);
                }
            }
            doc.reveal_new_tasks(id)?;
            Ok(id)
        })
    }
    pub fn validate_occurrence(&self, path: &[i64]) -> Result<(), String> {
        if path.is_empty()
            || !self.roots().contains(&path[0])
            || path.windows(2).any(|p| {
                !self
                    .links
                    .iter()
                    .any(|l| l.parent == p[0] && l.child == p[1])
            })
        {
            return Err(
                "This occurrence no longer exists. Select it again in the hierarchy.".into(),
            );
        }
        Ok(())
    }
    pub fn preview_item_action(
        &self,
        path: Vec<i64>,
        action: ItemAction,
    ) -> Result<ActionPreview, String> {
        self.validate_occurrence(&path)?;
        let id = *path.last().unwrap();
        let counts = self.appearance_counts();
        let blocking = if action == ItemAction::Unlink {
            path[..path.len() - 1]
                .iter()
                .find(|id| counts[id] != "1")
                .copied()
        } else {
            None
        };
        if action == ItemAction::Unlink && counts[&id] == "1" {
            return Err("This item has only one appearance. Use Delete instead.".into());
        }
        let mut deleted = BTreeSet::new();
        let mut retained = BTreeSet::new();
        if action == ItemAction::Delete {
            let children = adjacency(self);
            let mut remaining: BTreeMap<_, _> = self
                .placements()
                .into_iter()
                .map(|(id, p)| (id, p.count))
                .collect();
            deleted.insert(id);
            let mut queue = VecDeque::from([id]);
            while let Some(node) = queue.pop_front() {
                for &child in children.get(&node).into_iter().flatten() {
                    let n = remaining.get_mut(&child).unwrap();
                    *n -= 1;
                    if *n == 0 && deleted.insert(child) {
                        queue.push_back(child);
                    }
                }
            }
            for l in &self.links {
                if deleted.contains(&l.parent) && !deleted.contains(&l.child) {
                    retained.insert(l.child);
                }
            }
        }
        Ok(ActionPreview {
            document_id: self.document_id.clone(),
            revision: self.revision,
            id,
            path,
            action,
            blocking_parent: blocking,
            affected_view_ids: self
                .views
                .values()
                .filter(|v| {
                    v.filter
                        .container_rules()
                        .iter()
                        .any(|r| deleted.contains(&r.container_id))
                })
                .map(|v| v.id)
                .collect(),
            deleted_ids: deleted.into_iter().collect(),
            retained_child_ids: retained.into_iter().collect(),
            appearances: counts[&id].clone(),
        })
    }
    pub fn apply_item_action(
        &mut self,
        preview: &ActionPreview,
        confirmed: bool,
    ) -> Result<(), String> {
        if &self.preview_item_action(preview.path.clone(), preview.action.clone())? != preview {
            return Err("The collection changed. Review the action again.".into());
        }
        if (preview.action == ItemAction::Delete || preview.blocking_parent.is_some()) && !confirmed
        {
            return Err("Confirm this action before continuing.".into());
        }
        let snapshot = self.clone();
        self.transact(|doc| {
            doc.root_order = doc.roots();
            if preview.action == ItemAction::Delete {
                prune(doc, &preview.deleted_ids.iter().copied().collect());
            } else if let Some(blocking) = preview.blocking_parent {
                // Earliest shared ancestor is the only replaceable occurrence
                // whose incoming placement does not itself affect other paths.
                let index = preview.path.iter().position(|&id| id == blocking).unwrap();
                let copied = copy_branch(&snapshot, doc, blocking, None, true)?;
                if index == 0 {
                    let pos = doc
                        .root_order
                        .iter()
                        .position(|&id| id == blocking)
                        .unwrap();
                    doc.root_order[pos] = copied.root;
                } else {
                    let parent = preview.path[index - 1];
                    let edge = doc
                        .links
                        .iter_mut()
                        .find(|l| l.parent == parent && l.child == blocking)
                        .unwrap();
                    edge.child = copied.root;
                }
                let mut current = copied.root;
                for &child in &preview.path[index + 1..] {
                    current = copied.edges[&(current, child)];
                }
                let children = adjacency(doc);
                let mut removed = BTreeSet::from([current]);
                let mut queue = VecDeque::from([current]);
                while let Some(node) = queue.pop_front() {
                    for &child in children.get(&node).into_iter().flatten() {
                        if removed.insert(child) {
                            queue.push_back(child);
                        }
                    }
                }
                prune(doc, &removed);
            } else if preview.path.len() == 1 {
                doc.root_order.retain(|&id| id != preview.id);
            } else {
                let parent = preview.path[preview.path.len() - 2];
                doc.links
                    .retain(|l| !(l.parent == parent && l.child == preview.id));
            }
            Ok(())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::ItemKind;
    fn task(d: &mut Document, parent: Option<i64>) -> i64 {
        d.add_item(ItemKind::Task, "Task".into(), parent).unwrap()
    }
    #[test]
    fn exact_counts_include_shared_paths_and_do_not_overflow() {
        let mut d = Document::new("counts".into());
        let mut prev = task(&mut d, None);
        for _ in 0..140 {
            let a = task(&mut d, Some(prev));
            let b = task(&mut d, Some(prev));
            let c = task(&mut d, Some(a));
            d.link(b, c).unwrap();
            prev = c;
        }
        assert_eq!(
            d.appearance_counts()[&prev],
            "1393796574908163946345982392040522594123776"
        );
    }
    #[test]
    fn copying_depth_reuses_shallower_copy_and_never_changes_originals() {
        let mut d = Document::new("copy".into());
        let trip = task(&mut d, None);
        let packing = task(&mut d, Some(trip));
        let passport = task(&mut d, Some(trip));
        d.link(packing, passport).unwrap();
        let items = d.items.clone();
        let old_links = d.links.clone();
        let copy = d
            .link_or_copy(trip, None, true, Some(1), false, d.revision)
            .unwrap();
        let children: Vec<_> = d
            .links
            .iter()
            .filter(|l| l.parent == copy)
            .map(|l| l.child)
            .collect();
        assert_eq!(children.len(), 2);
        assert_eq!(d.items.len(), 6);
        assert!(d.links.contains(&Link {
            parent: children[0],
            child: children[1]
        }));
        for (id, item) in items {
            assert_eq!(d.items[&id], item);
        }
        assert!(old_links.iter().all(|l| d.links.contains(l)));
        let shallow = d
            .link_or_copy(trip, None, true, Some(0), false, d.revision)
            .unwrap();
        assert!(d.links.contains(&Link {
            parent: shallow,
            child: packing
        }));
    }
    #[test]
    fn full_independent_copy_and_self_destination_use_frozen_source() {
        let mut d = Document::new("copy".into());
        let root = task(&mut d, None);
        let a = task(&mut d, Some(root));
        let b = task(&mut d, Some(root));
        let shared = task(&mut d, Some(a));
        d.link(b, shared).unwrap();
        let before = d.clone();
        assert!(d
            .link_or_copy(root, Some(shared), true, Some(0), false, d.revision)
            .is_err());
        assert_eq!(d, before);
        assert!(d
            .link_or_copy(root, Some(root), false, None, false, d.revision)
            .is_err());
        assert_eq!(d, before);
        let new = d
            .link_or_copy(root, Some(root), true, None, true, d.revision)
            .unwrap();
        assert_eq!(d.items.len(), 9); // root, two branches, two independent leaves
        let new_children: Vec<_> = d
            .links
            .iter()
            .filter(|l| l.parent == new)
            .map(|l| l.child)
            .collect();
        let leaves: Vec<_> = d
            .links
            .iter()
            .filter(|l| new_children.contains(&l.parent))
            .map(|l| l.child)
            .collect();
        assert_ne!(leaves[0], leaves[1]);
        d.validate().unwrap();
    }
    #[test]
    fn global_delete_removes_all_placements_but_keeps_external_children_and_rules() {
        let mut d = Document::new("delete".into());
        let a = task(&mut d, None);
        let b = task(&mut d, None);
        let shared = task(&mut d, Some(a));
        d.link(b, shared).unwrap();
        let orphan = task(&mut d, Some(shared));
        let retained = task(&mut d, Some(shared));
        d.link(b, retained).unwrap();
        let view = d
            .add_view(
                "Inside".into(),
                crate::filter::FilterExpr::Folder {
                    folder_id: shared,
                    recursive: true,
                },
            )
            .unwrap();
        let p = d
            .preview_item_action(vec![a, shared], ItemAction::Delete)
            .unwrap();
        assert_eq!(p.appearances, "2");
        assert_eq!(p.deleted_ids, vec![shared, orphan]);
        assert_eq!(p.retained_child_ids, vec![retained]);
        assert_eq!(p.affected_view_ids, vec![view]);
        assert!(d.apply_item_action(&p, false).is_err());
        d.apply_item_action(&p, true).unwrap();
        assert!(d.items.contains_key(&retained));
        assert!(d.deleted_item_ids.contains(&shared));
    }
    #[test]
    fn blocked_unlink_replaces_earliest_shared_ancestor_and_prunes_only_copied_path() {
        let mut d = Document::new("unlink".into());
        let a = task(&mut d, None);
        let b = task(&mut d, None);
        let f = task(&mut d, Some(a));
        d.link(b, f).unwrap();
        let nested = task(&mut d, Some(f));
        let child = task(&mut d, Some(nested));
        let grandchild = task(&mut d, Some(child));
        let before = d.clone();
        let p = d
            .preview_item_action(vec![a, f, nested, child], ItemAction::Unlink)
            .unwrap();
        assert_eq!(p.blocking_parent, Some(f));
        assert!(d.apply_item_action(&p, false).is_err());
        assert_eq!(d, before);
        d.apply_item_action(&p, true).unwrap();
        assert!(d.links.contains(&Link {
            parent: b,
            child: f
        }));
        assert!(!d.links.contains(&Link {
            parent: a,
            child: f
        }));
        let copied = d.links.iter().find(|l| l.parent == a).unwrap().child;
        let copied_nested = d.links.iter().find(|l| l.parent == copied).unwrap().child;
        assert!(!d.links.iter().any(|l| l.parent == copied_nested));
        assert_eq!(d.items[&child], before.items[&child]);
        assert_eq!(d.items[&grandchild], before.items[&grandchild]);
        assert_eq!(d.items.len(), before.items.len() + 2);
        assert_eq!(d.roots(), before.roots());
    }
    #[test]
    fn normal_unlink_is_local_stale_confirmation_and_invalid_paths_fail_atomically() {
        let mut d = Document::new("unlink".into());
        let a = task(&mut d, None);
        let b = task(&mut d, None);
        let child = task(&mut d, Some(a));
        d.link_or_copy(child, Some(b), false, Some(0), false, d.revision)
            .unwrap();
        let p = d
            .preview_item_action(vec![a, child], ItemAction::Unlink)
            .unwrap();
        assert_eq!(p.blocking_parent, None);
        d.apply_item_action(&p, false).unwrap();
        assert!(d.links.contains(&Link { parent: b, child }));
        let before = d.clone();
        assert!(d.apply_item_action(&p, false).is_err());
        assert_eq!(d, before);
        assert!(d
            .preview_item_action(vec![a, child], ItemAction::Delete)
            .is_err());
        assert!(d
            .preview_item_action(vec![b, child], ItemAction::Unlink)
            .is_err());
    }
}

#[cfg(test)]
mod copy_preservation_tests {
    use super::*;
    use crate::model::{ContainerPreferences, ItemKind};
    use crate::settings::IndicatorOverrides;
    #[test]
    fn copies_preserve_all_fields_and_settings_and_links_keep_original_root() {
        let mut d = Document::new("preserve".into());
        let source = d.add_item(ItemKind::Task, "Original".into(), None).unwrap();
        let destination = d
            .add_item(ItemKind::Folder, "Destination".into(), None)
            .unwrap();
        let tag = d.add_tag("Travel".into()).unwrap();
        d.edit_item(
            source,
            "Original".into(),
            "Notes 日本".into(),
            Some("2026-12-01".into()),
            2,
            vec![tag],
        )
        .unwrap();
        d.set_auto_complete(source, true).unwrap();
        let defaults = IndicatorOverrides {
            total: Some(false),
            ..Default::default()
        };
        d.parent_indicator_defaults.insert(source, defaults.clone());
        d.set_container_preferences(
            1,
            source,
            ContainerPreferences {
                hide_completed: Some(false),
                ..Default::default()
            },
        )
        .unwrap();
        let new = d
            .link_or_copy(source, Some(destination), true, None, false, d.revision)
            .unwrap();
        let mut expected = d.items[&source].clone();
        expected.id = new;
        assert_eq!(d.items[&new], expected);
        assert_eq!(d.parent_indicator_defaults[&new], defaults);
        assert_eq!(
            d.views[&1].preferences[&new],
            d.views[&1].preferences[&source]
        );
        d.link_or_copy(source, Some(destination), false, Some(0), false, d.revision)
            .unwrap();
        assert!(d.roots().contains(&source));
        assert_eq!(d.appearance_counts()[&source], "2");
        let p = d
            .preview_item_action(vec![source], ItemAction::Unlink)
            .unwrap();
        d.apply_item_action(&p, false).unwrap();
        assert!(!d.roots().contains(&source));
        assert!(d.links.contains(&Link {
            parent: destination,
            child: source
        }));
    }
}
