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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub summary: Option<ihtd_core::indicators::ChildSummary>,
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
                summary: None,
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

/// Only the user-facing query requests summaries; move planning keeps the
/// projection lightweight. Collapsed parents still summarize direct children.
pub fn outline_with_summaries(
    document: &Document,
    view_id: i64,
    completed: bool,
    expanded: &BTreeSet<String>,
    today: &str,
) -> Result<Vec<Row>, String> {
    let mut rows = outline(document, view_id, completed, expanded)?;
    let mut metrics =
        ihtd_core::indicators::IndicatorQuery::new(document, view_id, completed, today)?;
    for row in &mut rows {
        row.summary = metrics.for_parent(row.id)?;
    }
    Ok(rows)
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

    #[test]
    fn summaries_ignore_context_descendants_and_expansion_and_use_strict_tab_membership() {
        let mut doc = Document::new("summaries".into());
        let p = doc
            .add_item(ItemKind::Folder, "Parent".into(), None)
            .unwrap();
        let context = doc
            .add_item(ItemKind::Task, "Context".into(), Some(p))
            .unwrap();
        doc.add_item(ItemKind::Task, "Match deep".into(), Some(context))
            .unwrap();
        let direct = doc
            .add_item(ItemKind::Task, "Match direct".into(), Some(p))
            .unwrap();
        doc.set_completed(direct, true, false).unwrap();
        doc.set_container_preferences(
            1,
            p,
            ContainerPreferences {
                hide_completed: Some(false),
                ..Default::default()
            },
        )
        .unwrap();
        doc.views.get_mut(&1).unwrap().filter = serde_json::from_value(serde_json::json!({
            "op":"text", "field":"title", "comparison":"contains", "value":"Match", "case_sensitive":false
        })).unwrap();
        let before = doc.clone();
        let open =
            outline_with_summaries(&doc, 1, false, &BTreeSet::from(["*".into()]), "2026-10-30")
                .unwrap();
        assert!(open.iter().any(|r| r.id == direct)); // visibility allows it
        let parent = open.iter().find(|r| r.id == p).unwrap();
        assert!(parent.context_only);
        assert_eq!(parent.summary.as_ref().unwrap().total, Some(0)); // but tab doesn't count it
        let collapsed =
            outline_with_summaries(&doc, 1, false, &BTreeSet::new(), "2026-10-30").unwrap();
        assert_eq!(collapsed.len(), 1);
        assert_eq!(collapsed[0].summary, parent.summary);
        let done = outline_with_summaries(&doc, 1, true, &BTreeSet::new(), "2026-10-30").unwrap();
        assert_eq!(done[0].summary.as_ref().unwrap().total, Some(1));
        assert_eq!(doc, before);
        assert!(outline(&doc, 1, false, &BTreeSet::new()).unwrap()[0]
            .summary
            .is_none());
    }
}
