use ihtd_core::model::{Document, ItemKind};
use std::collections::{BTreeMap, BTreeSet};

pub fn export(document: &Document, format: &str) -> Result<String, String> {
    match format {
        "json" => serde_json::to_string_pretty(document).map_err(|e| e.to_string()),
        "csv" => {
            let quote = |s: &str| format!("\"{}\"", s.replace('"', "\"\""));
            let mut text="id,kind,title,notes,due_date,priority,completed,auto_complete,tag_ids,parent_ids\r\n".to_string();
            for item in document.items.values() {
                let fields = vec![
                    item.id.to_string(),
                    if item.kind == ItemKind::Task {
                        "task"
                    } else {
                        "folder"
                    }
                    .into(),
                    item.title.clone(),
                    item.notes.clone(),
                    item.due_date.clone().unwrap_or_default(),
                    item.priority.to_string(),
                    item.completed.to_string(),
                    item.auto_complete.to_string(),
                    item.tag_ids
                        .iter()
                        .map(i64::to_string)
                        .collect::<Vec<_>>()
                        .join(";"),
                    document
                        .links
                        .iter()
                        .filter(|l| l.child == item.id)
                        .map(|l| l.parent.to_string())
                        .collect::<Vec<_>>()
                        .join(";"),
                ];
                text.push_str(
                    &fields
                        .iter()
                        .map(|s| quote(s))
                        .collect::<Vec<_>>()
                        .join(","),
                );
                text.push_str("\r\n");
            }
            Ok(text)
        }
        "markdown" => {
            let mut text=format!("# IHTD collection\n\nDocument: `{}`\n\nShared appearances carry the same item ID.\n\n",document.document_id);
            let mut children: BTreeMap<i64, Vec<i64>> = BTreeMap::new();
            let mut placed = BTreeSet::new();
            for link in &document.links {
                children.entry(link.parent).or_default().push(link.child);
                placed.insert(link.child);
            }
            let mut stack: Vec<_> = document
                .roots()
                .into_iter()
                .rev()
                .map(|id| (id, 0usize))
                .collect();
            while let Some((id, depth)) = stack.pop() {
                let item = &document.items[&id];
                let title = item
                    .title
                    .replace(['\r', '\n'], " ")
                    .replace('[', "\\[")
                    .replace(']', "\\]");
                let prefix = if item.kind == ItemKind::Folder {
                    "-"
                } else if item.completed {
                    "- [x]"
                } else {
                    "- [ ]"
                };
                text.push_str(&format!(
                    "{}{} {} (#{})\n",
                    "  ".repeat(depth),
                    prefix,
                    title,
                    id
                ));
                if !item.notes.is_empty() {
                    for line in item.notes.lines() {
                        text.push_str(&format!("{}> {}\n", "  ".repeat(depth + 1), line));
                    }
                }
                if let Some(list) = children.get(&id) {
                    for &child in list.iter().rev() {
                        stack.push((child, depth + 1));
                    }
                }
            }
            Ok(text)
        }
        _ => Err("Choose JSON, Markdown, or CSV export".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn json_keeps_shared_identity_and_text_exports_escape_data() {
        let mut doc = Document::new("export".into());
        let a = doc.add_item(ItemKind::Folder, "A".into(), None).unwrap();
        let b = doc.add_item(ItemKind::Folder, "B".into(), None).unwrap();
        let t = doc
            .add_item(ItemKind::Task, "Quoted, \"task\"".into(), Some(a))
            .unwrap();
        doc.link(b, t).unwrap();
        doc.edit_item(
            t,
            "Quoted, \"task\"".into(),
            "Line 1\nLine 2".into(),
            None,
            3,
            vec![],
        )
        .unwrap();
        assert_eq!(
            serde_json::from_str::<Document>(&export(&doc, "json").unwrap()).unwrap(),
            doc
        );
        assert_eq!(
            export(&doc, "markdown")
                .unwrap()
                .matches(&format!("(#{t})"))
                .count(),
            2
        );
        let csv = export(&doc, "csv").unwrap();
        assert!(csv.contains("\"Quoted, \"\"task\"\"\""));
        assert!(csv.contains("\"Line 1\nLine 2\""));
    }
}
