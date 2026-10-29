//! View-specific ordering over the collection's one shared manual sequence.
use crate::model::{Document, ItemKind};
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SortMode {
    #[default]
    Manual,
    Title,
    DueDate,
    Priority,
}
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct SortSpec {
    pub mode: SortMode,
    pub descending: bool,
}
impl SortSpec {
    pub fn validate(self) -> Result<(), String> {
        if self.mode == SortMode::Manual && self.descending {
            return Err("Manual order has no ascending/descending direction.".into());
        }
        Ok(())
    }
}
fn direction(order: Ordering, descending: bool) -> Ordering {
    if descending {
        order.reverse()
    } else {
        order
    }
}
fn optional<T: Ord>(a: Option<T>, b: Option<T>, descending: bool) -> Ordering {
    match (a, b) {
        (Some(a), Some(b)) => direction(a.cmp(&b), descending),
        (None, Some(_)) => Ordering::Greater,
        (Some(_), None) => Ordering::Less,
        (None, None) => Ordering::Equal,
    }
}
impl Document {
    pub fn sort_spec(&self, view: i64, parent: Option<i64>) -> Result<SortSpec, String> {
        if let Some(id) = parent {
            if !self.items.contains_key(&id) {
                return Err("Sorting parent no longer exists.".into());
            }
        }
        let view = self
            .views
            .get(&view)
            .ok_or("Sorting view no longer exists.")?;
        Ok(view
            .sorting
            .get(&parent.unwrap_or(0))
            .copied()
            .unwrap_or_default())
    }
    pub fn set_sort(
        &mut self,
        view: i64,
        parent: Option<i64>,
        expected: SortSpec,
        sort: SortSpec,
    ) -> Result<(), String> {
        self.transact(|doc| {
            if doc.sort_spec(view, parent)? != expected {
                return Err("Sorting changed. Reopen sorting to review it.".into());
            }
            sort.validate()?;
            let map = &mut doc.views.get_mut(&view).unwrap().sorting;
            if sort == SortSpec::default() {
                map.remove(&parent.unwrap_or(0));
            } else {
                map.insert(parent.unwrap_or(0), sort);
            }
            Ok(())
        })
    }
    pub fn manual_siblings(&self, parent: Option<i64>) -> Vec<i64> {
        match parent {
            Some(parent) => self
                .links
                .iter()
                .filter(|l| l.parent == parent)
                .map(|l| l.child)
                .collect(),
            None => self.roots(),
        }
    }
    pub fn order_siblings(
        &self,
        view: i64,
        parent: Option<i64>,
        ids: &mut [i64],
    ) -> Result<(), String> {
        let sort = self.sort_spec(view, parent)?;
        if sort.mode == SortMode::Manual {
            return Ok(());
        }
        let manual: BTreeMap<_, _> = ids.iter().enumerate().map(|(i, &id)| (id, i)).collect();
        let titles: BTreeMap<_, _> = ids
            .iter()
            .map(|&id| (id, self.items[&id].title.to_lowercase()))
            .collect();
        ids.sort_by(|a, b| {
            let (a_item, b_item) = (&self.items[a], &self.items[b]);
            let kind = (a_item.kind != ItemKind::Folder).cmp(&(b_item.kind != ItemKind::Folder));
            if kind != Ordering::Equal {
                return kind;
            }
            let key = match sort.mode {
                SortMode::Manual => Ordering::Equal,
                SortMode::Title => direction(titles[a].cmp(&titles[b]), sort.descending),
                SortMode::DueDate => optional(
                    a_item.due_date.as_deref(),
                    b_item.due_date.as_deref(),
                    sort.descending,
                ),
                SortMode::Priority => optional(
                    (a_item.priority != 0).then_some(a_item.priority),
                    (b_item.priority != 0).then_some(b_item.priority),
                    sort.descending,
                ),
            };
            key.then_with(|| titles[a].cmp(&titles[b]))
                .then_with(|| manual[a].cmp(&manual[b]))
        });
        Ok(())
    }
    pub fn sorted_siblings(&self, view: i64, parent: Option<i64>) -> Result<Vec<i64>, String> {
        let mut ids = self.manual_siblings(parent);
        self.order_siblings(view, parent, &mut ids)?;
        Ok(ids)
    }
    pub(crate) fn validate_sorting(&self) -> Result<(), String> {
        for view in self.views.values() {
            for (&id, &sort) in &view.sorting {
                if id != 0 && !self.items.contains_key(&id) {
                    return Err("Sorting refers to a missing parent.".into());
                }
                sort.validate()?;
            }
        }
        Ok(())
    }
    pub(crate) fn write_manual_order(
        &mut self,
        parent: Option<i64>,
        order: &[i64],
    ) -> Result<(), String> {
        let mut saved = self.manual_siblings(parent);
        let mut supplied = order.to_vec();
        saved.sort_unstable();
        supplied.sort_unstable();
        if saved != supplied {
            return Err("Sibling membership changed while ordering.".into());
        }
        match parent {
            None => self.root_order = order.to_vec(),
            Some(parent) => {
                let mut next = order.iter();
                for link in &mut self.links {
                    if link.parent == parent {
                        link.child = *next.next().ok_or("Invalid order")?;
                    }
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn add(
        d: &mut Document,
        title: &str,
        kind: ItemKind,
        date: Option<&str>,
        priority: u8,
        parent: Option<i64>,
    ) -> i64 {
        let id = d.add_item(kind, title.into(), parent).unwrap();
        d.edit_item(
            id,
            title.into(),
            String::new(),
            date.map(str::to_owned),
            priority,
            vec![],
        )
        .unwrap();
        id
    }
    #[test]
    fn modes_are_per_view_parent_and_root_with_no_mutation_of_manual_order() {
        let mut d = Document::new("sort".into());
        let z = add(&mut d, "Zulu", ItemKind::Task, None, 0, None);
        let a = add(&mut d, "alpha", ItemKind::Task, None, 0, None);
        let f = add(&mut d, "Folder", ItemKind::Folder, None, 0, None);
        let child_z = add(&mut d, "Z", ItemKind::Task, None, 0, Some(f));
        let child_a = add(&mut d, "A", ItemKind::Task, None, 0, Some(f));
        let second = d
            .add_view("Second".into(), crate::filter::FilterExpr::All)
            .unwrap();
        let manual = SortSpec::default();
        let title = SortSpec {
            mode: SortMode::Title,
            descending: false,
        };
        d.set_sort(1, None, manual, title).unwrap();
        assert_eq!(d.sorted_siblings(1, None).unwrap(), [f, a, z]);
        assert_eq!(d.sorted_siblings(second, None).unwrap(), [z, a, f]);
        assert_eq!(d.sorted_siblings(1, Some(f)).unwrap(), [child_z, child_a]);
        assert_eq!(d.manual_siblings(None), [z, a, f]);
        d.set_sort(
            1,
            Some(f),
            manual,
            SortSpec {
                descending: true,
                ..title
            },
        )
        .unwrap();
        assert_eq!(d.sorted_siblings(1, Some(f)).unwrap(), [child_z, child_a]);
        assert!(d.set_sort(1, None, manual, title).is_err());
        d.set_sort(1, None, title, manual).unwrap();
        assert_eq!(d.sorted_siblings(1, None).unwrap(), [z, a, f]);
    }
    #[test]
    fn absent_values_stay_last_both_directions_and_ties_use_title_then_manual() {
        let mut d = Document::new("sort".into());
        let none = add(&mut d, "A none", ItemKind::Task, None, 0, None);
        let b = add(&mut d, "Beta", ItemKind::Task, Some("2026-12-01"), 2, None);
        let a1 = add(&mut d, "Alpha", ItemKind::Task, Some("2026-12-01"), 2, None);
        let a2 = add(&mut d, "Alpha", ItemKind::Task, Some("2026-12-01"), 2, None);
        let early = add(
            &mut d,
            "Earlier",
            ItemKind::Task,
            Some("2026-01-01"),
            1,
            None,
        );
        let folder = add(&mut d, "Z folder", ItemKind::Folder, None, 0, None);
        for mode in [SortMode::DueDate, SortMode::Priority] {
            let mut previous = SortSpec::default();
            for descending in [false, true] {
                let spec = SortSpec { mode, descending };
                d.set_sort(1, None, previous, spec).unwrap();
                previous = spec;
                let sorted = d.sorted_siblings(1, None).unwrap();
                assert_eq!(sorted[0], folder);
                assert_eq!(sorted.last(), Some(&none));
                let eligible = if descending {
                    vec![folder, a1, a2, b, early, none]
                } else {
                    vec![folder, early, a1, a2, b, none]
                };
                assert_eq!(sorted, eligible);
            }
            d.set_sort(1, None, previous, SortSpec::default()).unwrap();
        }
    }
}

impl Document {
    /// Reorder only displayed siblings into their original manual slots. Hidden
    /// siblings keep their slots; a new incoming visible slot is appended.
    pub fn move_in_view(
        &mut self,
        view: i64,
        id: i64,
        source: Option<i64>,
        destination: Option<i64>,
        before: Option<i64>,
        reorder: bool,
        displayed: &[i64],
    ) -> Result<(), String> {
        let old = self.manual_siblings(destination);
        let spec = self.sort_spec(view, destination)?;
        if source != destination
            && source.is_some_and(|parent| {
                self.appearance_counts()
                    .get(&parent)
                    .is_some_and(|n| n != "1")
            })
        {
            return Err("This parent appears in multiple places. Moving its child out would remove it from every appearance. Create an independent copy of the linked parent and its children first. You can still reorder children within the shared parent.".into());
        }

        let shown: std::collections::BTreeSet<_> = displayed.iter().copied().collect();
        if shown.len() != displayed.len() || displayed.iter().any(|id| !old.contains(id)) {
            return Err("Displayed siblings changed. Review the drop position.".into());
        }
        if reorder && before.is_some_and(|id| !shown.contains(&id)) {
            return Err("The insertion target is no longer displayed.".into());
        }
        self.transact(|doc| {
            doc.move_item(id, source, destination, before)?;
            if reorder {
                let mut visible: Vec<_> = displayed.iter().copied().filter(|&v| v != id).collect();
                let index = before
                    .and_then(|target| visible.iter().position(|&v| v == target))
                    .unwrap_or(visible.len());
                visible.insert(index, id);
                let mut pending = visible.into_iter();
                let mut result = Vec::new();
                for &old_id in &old {
                    if shown.contains(&old_id) || old_id == id {
                        if let Some(next) = pending.next() {
                            result.push(next);
                        }
                    } else {
                        result.push(old_id);
                    }
                }
                result.extend(pending);
                doc.write_manual_order(destination, &result)?;
                if spec.mode != SortMode::Manual {
                    doc.views
                        .get_mut(&view)
                        .unwrap()
                        .sorting
                        .remove(&destination.unwrap_or(0));
                }
            }
            Ok(())
        })
    }
}

#[cfg(test)]
mod move_tests {
    use super::*;
    fn add(d: &mut Document, name: &str, parent: Option<i64>) -> i64 {
        d.add_item(ItemKind::Task, name.into(), parent).unwrap()
    }
    #[test]
    fn automatic_drop_uses_displayed_order_with_hidden_slots_and_only_switches_current_parent_view()
    {
        let mut d = Document::new("drop".into());
        let hidden = add(&mut d, "Hidden", None);
        let z = add(&mut d, "Z", None);
        let middle = add(&mut d, "Hidden middle", None);
        let b = add(&mut d, "B", None);
        let a = add(&mut d, "A", None);
        let other = d
            .add_view("Other".into(), crate::filter::FilterExpr::All)
            .unwrap();
        let spec = SortSpec {
            mode: SortMode::Title,
            descending: false,
        };
        d.set_sort(1, None, SortSpec::default(), spec).unwrap();
        d.set_sort(other, None, SortSpec::default(), spec).unwrap();
        d.move_in_view(1, z, None, None, Some(b), true, &[a, b, z])
            .unwrap();
        assert_eq!(d.roots(), [hidden, a, middle, z, b]);
        assert_eq!(d.sort_spec(1, None).unwrap(), SortSpec::default());
        assert_eq!(d.sort_spec(other, None).unwrap(), spec);
        assert_eq!(
            d.sorted_siblings(other, None).unwrap(),
            [a, b, hidden, middle, z]
        );
        // Manual filtered reorders follow the same hidden-slot guarantee.
        d.move_in_view(1, a, None, None, None, true, &[a, z, b])
            .unwrap();
        assert_eq!(d.roots(), [hidden, z, middle, b, a]);
    }
    #[test]
    fn incoming_insert_coalesces_existing_links_and_container_drop_keeps_auto_mode() {
        let mut d = Document::new("drop".into());
        let p = add(&mut d, "Parent", None);
        let incoming = add(&mut d, "Incoming", None);
        let h = add(&mut d, "Hidden", Some(p));
        let z = add(&mut d, "Z", Some(p));
        let a = add(&mut d, "A", Some(p));
        let spec = SortSpec {
            mode: SortMode::Title,
            descending: false,
        };
        d.set_sort(1, Some(p), SortSpec::default(), spec).unwrap();
        d.move_in_view(1, incoming, None, Some(p), Some(a), true, &[a, z])
            .unwrap();
        assert_eq!(d.manual_siblings(Some(p)), [h, incoming, a, z]);
        assert_eq!(d.sort_spec(1, Some(p)).unwrap(), SortSpec::default());
        let new = add(&mut d, "New", None);
        d.set_sort(1, Some(p), SortSpec::default(), spec).unwrap();
        d.move_in_view(1, new, None, Some(p), None, false, &[])
            .unwrap();
        assert_eq!(d.sort_spec(1, Some(p)).unwrap(), spec);
        let before = d.clone();
        assert!(d
            .move_in_view(1, a, Some(p), Some(p), Some(h), true, &[a, z])
            .is_err());
        assert_eq!(d, before);
    }
}

#[cfg(test)]
mod shared_parent_tests {
    use super::*;
    #[test]
    fn shared_ancestor_prevents_moving_out_but_allows_shared_reordering() {
        let mut d = Document::new("shared".into());
        let a = d.add_item(ItemKind::Folder, "A".into(), None).unwrap();
        let b = d.add_item(ItemKind::Folder, "B".into(), None).unwrap();
        let f = d.add_item(ItemKind::Folder, "F".into(), Some(a)).unwrap();
        d.link(b, f).unwrap();
        let nested = d
            .add_item(ItemKind::Folder, "Nested".into(), Some(f))
            .unwrap();
        let child = d
            .add_item(ItemKind::Task, "Child".into(), Some(nested))
            .unwrap();
        let other = d
            .add_item(ItemKind::Task, "Other".into(), Some(nested))
            .unwrap();
        let before = d.clone();
        assert!(d
            .move_in_view(1, child, Some(nested), None, None, false, &[])
            .unwrap_err()
            .contains("independent copy"));
        assert_eq!(d, before);
        d.move_in_view(
            1,
            child,
            Some(nested),
            Some(nested),
            None,
            true,
            &[child, other],
        )
        .unwrap();
        assert_eq!(d.manual_siblings(Some(nested)), [other, child]);
    }
}

#[cfg(test)]
mod preservation_tests {
    use super::*;
    use crate::hierarchy::ItemAction;
    #[test]
    fn copying_parent_sort_choices_and_deleting_stale_keys_preserves_other_scopes() {
        let mut d = Document::new("sort retention".into());
        let parent = d.add_item(ItemKind::Folder, "Folder".into(), None).unwrap();
        d.add_item(ItemKind::Task, "Child".into(), Some(parent))
            .unwrap();
        let title = SortSpec {
            mode: SortMode::Title,
            descending: true,
        };
        let priority = SortSpec {
            mode: SortMode::Priority,
            descending: false,
        };
        d.set_sort(1, None, SortSpec::default(), title).unwrap();
        d.set_sort(1, Some(parent), SortSpec::default(), priority)
            .unwrap();
        let copied = d
            .link_or_copy(parent, None, true, None, false, d.revision)
            .unwrap();
        assert_eq!(d.sort_spec(1, Some(copied)).unwrap(), priority);
        let preview = d
            .preview_item_action(vec![parent], ItemAction::Delete)
            .unwrap();
        d.apply_item_action(&preview, true).unwrap();
        assert!(!d.views[&1].sorting.contains_key(&parent));
        assert_eq!(d.sort_spec(1, None).unwrap(), title);
        assert_eq!(d.sort_spec(1, Some(copied)).unwrap(), priority);
        d.validate().unwrap();
    }
}
