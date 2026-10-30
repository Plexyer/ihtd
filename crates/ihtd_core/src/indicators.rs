//! Read-only direct-child metrics. Settings, filtering and tab semantics live
//! here once; hosts supply only their local calendar date.
use crate::model::{Document, ItemKind};
use chrono::NaiveDate;
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize)]
pub struct ChildSummary {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub high_priority: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub medium_priority: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub low_priority: Option<usize>,
    // Absent = disabled; Some(None) = enabled without a qualifying date.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_due_date: Option<Option<String>>,
}

pub struct IndicatorQuery<'a> {
    document: &'a Document,
    view: i64,
    completed: bool,
    today: String,
    children: BTreeMap<i64, Vec<i64>>,
    cache: BTreeMap<i64, Option<ChildSummary>>,
}
impl<'a> IndicatorQuery<'a> {
    pub fn new(
        document: &'a Document,
        view: i64,
        completed: bool,
        today: &str,
    ) -> Result<Self, String> {
        if !document.views.contains_key(&view) {
            return Err("View no longer exists.".into());
        }
        let date = NaiveDate::parse_from_str(today, "%Y-%m-%d")
            .map_err(|_| "Supply a valid local date for summary indicators.")?;
        if date.format("%Y-%m-%d").to_string() != today {
            return Err("Supply a canonical local date for summary indicators.".into());
        }
        let mut children: BTreeMap<i64, Vec<i64>> = BTreeMap::new();
        for link in &document.links {
            children.entry(link.parent).or_default().push(link.child);
        }
        Ok(Self {
            document,
            view,
            completed,
            today: today.into(),
            children,
            cache: BTreeMap::new(),
        })
    }
    pub fn for_parent(&mut self, parent: i64) -> Result<Option<ChildSummary>, String> {
        if let Some(summary) = self.cache.get(&parent) {
            return Ok(summary.clone());
        }
        let settings = self.document.resolved_indicators(parent, self.view)?;
        let summary = if let Some(children) = self.children.get(&parent) {
            let mut summary = ChildSummary {
                total: settings.total.then_some(0),
                completed: (settings.total && settings.completed_ratio).then_some(0),
                high_priority: settings.high_priority.then_some(0),
                medium_priority: settings.medium_priority.then_some(0),
                low_priority: settings.low_priority.then_some(0),
                next_due_date: settings.next_due_date.then_some(None),
            };
            if summary == ChildSummary::default() {
                // No matching, counting or date work when all consumers are off.
                None
            } else {
                for id in children {
                    let item = &self.document.items[id];
                    if item.kind != ItemKind::Task
                        || !self.document.views[&self.view]
                            .filter
                            .matches(item, self.document)
                    {
                        continue;
                    }
                    let in_tab = item.completed == self.completed;
                    if let Some(total) = &mut summary.total {
                        if settings.completed_ratio || in_tab {
                            *total += 1;
                        }
                    }
                    if let Some(done) = &mut summary.completed {
                        *done += usize::from(item.completed);
                    }
                    if !in_tab {
                        continue;
                    }
                    if settings.high_priority || settings.medium_priority || settings.low_priority {
                        let counter = match item.priority {
                            3 => &mut summary.high_priority,
                            2 => &mut summary.medium_priority,
                            1 => &mut summary.low_priority,
                            _ => &mut None,
                        };
                        if let Some(value) = counter {
                            *value += 1;
                        }
                    }
                    if let Some(next) = &mut summary.next_due_date {
                        if let Some(date) = &item.due_date {
                            if date >= &self.today && next.as_ref().is_none_or(|old| date < old) {
                                *next = Some(date.clone());
                            }
                        }
                    }
                }
                Some(summary)
            }
        } else {
            None
        };
        self.cache.insert(parent, summary.clone());
        Ok(summary)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{filter::FilterExpr, settings::IndicatorOverrides};
    fn task(
        d: &mut Document,
        parent: i64,
        title: &str,
        priority: u8,
        done: bool,
        date: Option<&str>,
    ) -> i64 {
        let id = d
            .add_item(ItemKind::Task, title.into(), Some(parent))
            .unwrap();
        d.edit_item(
            id,
            title.into(),
            String::new(),
            date.map(str::to_owned),
            priority,
            vec![],
        )
        .unwrap();
        if done {
            d.set_completed(id, true, false).unwrap();
        }
        id
    }
    fn summary(d: &Document, view: i64, parent: i64, done: bool) -> ChildSummary {
        IndicatorQuery::new(d, view, done, "2026-10-30")
            .unwrap()
            .for_parent(parent)
            .unwrap()
            .unwrap()
    }
    #[test]
    fn direct_matching_tasks_only_ratio_ignores_tab_but_other_metrics_do_not() {
        let mut d = Document::new("metrics".into());
        let p = d.add_item(ItemKind::Folder, "Parent".into(), None).unwrap();
        let a = task(&mut d, p, "eligible", 3, false, Some("2026-10-29"));
        task(&mut d, p, "eligible", 2, false, Some("2026-10-31"));
        task(&mut d, p, "eligible", 1, true, Some("2026-10-30"));
        task(&mut d, p, "excluded", 3, false, Some("2026-10-30"));
        let f = d
            .add_item(ItemKind::Folder, "eligible".into(), Some(p))
            .unwrap();
        task(&mut d, f, "eligible", 3, false, Some("2026-10-30"));
        task(&mut d, a, "eligible", 3, false, Some("2026-10-30"));
        d.views.get_mut(&1).unwrap().filter = serde_json::from_value(serde_json::json!({"op":"text","field":"title","comparison":"equals","value":"eligible","case_sensitive":false})).unwrap();
        let s = &mut d.collection_settings.indicators;
        s.completed_ratio = true;
        s.low_priority = true;
        s.medium_priority = true;
        s.next_due_date = true;
        let before = d.clone();
        let unfinished = summary(&d, 1, p, false);
        assert_eq!(unfinished.total, Some(3));
        assert_eq!(unfinished.completed, Some(1));
        assert_eq!(unfinished.high_priority, Some(1));
        assert_eq!(unfinished.medium_priority, Some(1));
        assert_eq!(unfinished.low_priority, Some(0));
        assert_eq!(unfinished.next_due_date, Some(Some("2026-10-31".into())));
        let done = summary(&d, 1, p, true);
        assert_eq!(done.total, Some(3));
        assert_eq!(done.completed, Some(1));
        assert_eq!(done.high_priority, Some(0));
        assert_eq!(done.low_priority, Some(1));
        assert_eq!(done.next_due_date, Some(Some("2026-10-30".into())));
        d.collection_settings.indicators.completed_ratio = false;
        assert_eq!(summary(&d, 1, p, true).total, Some(1));
        d.collection_settings.indicators.completed_ratio = true;
        assert_eq!(d, before); // Queries never change stored data/revision.
    }
    #[test]
    fn shared_paths_count_each_direct_link_once_and_resolve_each_view_independently() {
        let mut d = Document::new("shared".into());
        let a = d.add_item(ItemKind::Folder, "A".into(), None).unwrap();
        let b = d.add_item(ItemKind::Folder, "B".into(), None).unwrap();
        let f = d.add_item(ItemKind::Folder, "F".into(), Some(a)).unwrap();
        d.link(b, f).unwrap();
        let t = task(&mut d, f, "Child", 3, false, None);
        d.link(a, t).unwrap();
        let v = d.add_view("Other".into(), FilterExpr::All).unwrap();
        assert_eq!(summary(&d, 1, f, false).total, Some(1));
        assert_eq!(summary(&d, 1, a, false).total, Some(1)); // folder F excluded
        let shared = IndicatorOverrides {
            high_priority: Some(false),
            ..Default::default()
        };
        let local = IndicatorOverrides {
            total: Some(false),
            ..Default::default()
        };
        d.set_indicator_settings(
            f,
            1,
            &Default::default(),
            &Default::default(),
            shared,
            local,
        )
        .unwrap();
        assert!(IndicatorQuery::new(&d, 1, false, "2026-10-30")
            .unwrap()
            .for_parent(f)
            .unwrap()
            .is_none());
        assert_eq!(summary(&d, v, f, false).high_priority, None);
        assert_eq!(summary(&d, v, f, false).total, Some(1));
    }
    #[test]
    fn disabled_metrics_are_absent_enabled_zeroes_remain_and_no_date_is_explicit_null() {
        let mut d = Document::new("none".into());
        let p = d.add_item(ItemKind::Task, "Parent".into(), None).unwrap();
        let t = task(&mut d, p, "Child", 0, true, Some("2026-10-29"));
        let s = summary(&d, 1, p, false);
        assert_eq!(
            serde_json::to_value(s).unwrap(),
            serde_json::json!({"total":0,"high_priority":0})
        );
        d.collection_settings.indicators.next_due_date = true;
        assert_eq!(summary(&d, 1, p, true).next_due_date, Some(None));
        let mut q = IndicatorQuery::new(&d, 1, true, "2026-10-30").unwrap();
        assert!(q.for_parent(t).unwrap().is_none());
        assert!(IndicatorQuery::new(&d, 1, false, "2026-02-30").is_err());
        assert!(IndicatorQuery::new(&d, 1, false, "2026-1-1").is_err());
    }
}
