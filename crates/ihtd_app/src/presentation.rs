use ihtd_core::model::{Document, ItemKind};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Serialize, Debug)]
pub struct Row {
    pub id: i64,
    pub depth: usize,
    pub parent_id: Option<i64>,
    pub placement_count: usize,
    pub path: String,
    pub has_children: bool,
    pub context_only: bool,
    pub expanded: bool,
}
struct Entry {
    row: Row,
    parent: Option<usize>,
    matches: bool,
    keep: bool,
}

pub fn outline(
    document: &Document,
    view_id: i64,
    completed: bool,
    expanded: &BTreeSet<String>,
) -> Result<Vec<Row>, String> {
    let view = document
        .views
        .get(&view_id)
        .ok_or("Select an existing view")?;
    let mut children: BTreeMap<i64, Vec<i64>> = BTreeMap::new();
    let mut placed = BTreeSet::new();
    for link in &document.links {
        children.entry(link.parent).or_default().push(link.child);
        placed.insert(link.child);
    }
    for (&parent, ids) in &mut children {
        document.order_siblings(view_id, Some(parent), ids)?;
    }
    let roots = document.sorted_siblings(view_id, None)?;
    let placements = document.placements();
    let mut stack: Vec<_> = roots
        .into_iter()
        .rev()
        .map(|id| (id, None, 0, String::new(), true, true))
        .collect();
    let mut entries: Vec<Entry> = Vec::new();
    while let Some((id, parent, depth, prefix, parent_hides, inherited)) = stack.pop() {
        let item = &document.items[&id];
        let prefs = view.preferences.get(&id).cloned().unwrap_or_default();
        let folder_done = item.kind == ItemKind::Folder && prefs.folder_hidden;
        if !completed && folder_done && parent_hides {
            continue;
        }
        let path = if prefix.is_empty() {
            id.to_string()
        } else {
            format!("{prefix}/{id}")
        };
        let is_done = item.completed || folder_done;
        let matches = view.filter.matches(item, document)
            && if completed {
                is_done
            } else {
                !is_done || !parent_hides
            };
        let opened = !expanded.contains(&format!("!{path}"))
            && (expanded.contains("*") || expanded.contains(&path));
        let index = entries.len();
        entries.push(Entry {
            row: Row {
                id,
                depth,
                parent_id: parent.map(|index: usize| entries[index].row.id),
                placement_count: placements[&id].count,
                path: path.clone(),
                has_children: false,
                context_only: !matches,
                expanded: opened,
            },
            parent,
            matches,
            keep: matches,
        });
        let hides = prefs.hide_completed.unwrap_or(inherited);
        let next_inherited = if prefs.inherit_hide_completed {
            hides
        } else {
            inherited
        };
        if let Some(descendants) = children.get(&id) {
            for &child in descendants.iter().rev() {
                stack.push((
                    child,
                    Some(index),
                    depth + 1,
                    path.clone(),
                    hides,
                    next_inherited,
                ));
            }
        }
    }
    for index in (0..entries.len()).rev() {
        if entries[index].keep {
            if let Some(parent) = entries[index].parent {
                entries[parent].keep = true;
                entries[parent].row.has_children = true;
            }
        }
    }
    let mut shown = vec![false; entries.len()];
    for index in 0..entries.len() {
        shown[index] = entries[index].keep
            && entries[index]
                .parent
                .map(|p| shown[p] && entries[p].row.expanded)
                .unwrap_or(true);
    }
    Ok(entries
        .into_iter()
        .enumerate()
        .filter_map(|(i, mut entry)| {
            entry.row.context_only = !entry.matches;
            shown[i].then_some(entry.row)
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use ihtd_core::model::ContainerPreferences;
    #[test]
    fn completed_outline_keeps_unfinished_ancestors_and_view_settings_are_independent() {
        let mut doc = Document::new("views".into());
        let p = doc.add_item(ItemKind::Folder, "P".into(), None).unwrap();
        let t = doc.add_item(ItemKind::Task, "T".into(), Some(p)).unwrap();
        doc.set_completed(t, true, false).unwrap();
        let expanded = BTreeSet::from(["*".into()]);
        let done = outline(&doc, 1, true, &expanded).unwrap();
        assert_eq!(done.len(), 2);
        assert!(done[0].context_only);
        assert!(!done[1].context_only);
        let v = doc.add_view("Keep".into(), Default::default()).unwrap();
        doc.set_container_preferences(
            v,
            p,
            ContainerPreferences {
                hide_completed: Some(false),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(outline(&doc, 1, false, &expanded).unwrap().len(), 1);
        assert_eq!(outline(&doc, v, false, &expanded).unwrap().len(), 2);
    }
}
