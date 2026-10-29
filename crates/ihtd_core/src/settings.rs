//! Collection-owned settings and per-indicator inheritance, shared by all hosts.
use crate::model::Document;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct IndicatorSettings {
    pub total: bool,
    pub completed_ratio: bool,
    pub high_priority: bool,
    pub medium_priority: bool,
    pub low_priority: bool,
    pub next_due_date: bool,
}
impl Default for IndicatorSettings {
    fn default() -> Self {
        Self {
            total: true,
            completed_ratio: false,
            high_priority: true,
            medium_priority: false,
            low_priority: false,
            next_due_date: false,
        }
    }
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct IndicatorOverrides {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_ratio: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub high_priority: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub medium_priority: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub low_priority: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_due_date: Option<bool>,
}
impl IndicatorOverrides {
    pub fn is_empty(&self) -> bool {
        self == &Self::default()
    }
    pub fn apply(&self, base: &IndicatorSettings) -> IndicatorSettings {
        IndicatorSettings {
            total: self.total.unwrap_or(base.total),
            completed_ratio: self.completed_ratio.unwrap_or(base.completed_ratio),
            high_priority: self.high_priority.unwrap_or(base.high_priority),
            medium_priority: self.medium_priority.unwrap_or(base.medium_priority),
            low_priority: self.low_priority.unwrap_or(base.low_priority),
            next_due_date: self.next_due_date.unwrap_or(base.next_due_date),
        }
    }
}
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(default, deny_unknown_fields)]
pub struct CollectionSettings {
    pub tag_suggestion_count: u32,
    pub tag_half_life_days: u32,
    pub indicators: IndicatorSettings,
}
impl Default for CollectionSettings {
    fn default() -> Self {
        Self {
            tag_suggestion_count: 5,
            tag_half_life_days: 3,
            indicators: IndicatorSettings::default(),
        }
    }
}
impl CollectionSettings {
    pub fn is_default(&self) -> bool {
        self == &Self::default()
    }
    pub fn validate(&self) -> Result<(), String> {
        if self.tag_half_life_days == 0 {
            return Err("Tag fading period must be at least one day.".into());
        }
        Ok(())
    }
}
impl Document {
    pub fn resolved_indicators(&self, item: i64, view: i64) -> Result<IndicatorSettings, String> {
        if !self.items.contains_key(&item) {
            return Err("Item no longer exists.".into());
        }
        let view = self.views.get(&view).ok_or("View no longer exists.")?;
        let shared = self
            .parent_indicator_defaults
            .get(&item)
            .cloned()
            .unwrap_or_default()
            .apply(&self.collection_settings.indicators);
        Ok(view
            .preferences
            .get(&item)
            .map(|p| p.indicators.apply(&shared))
            .unwrap_or(shared))
    }
    pub fn set_collection_settings(
        &mut self,
        expected: &CollectionSettings,
        settings: CollectionSettings,
    ) -> Result<(), String> {
        self.transact(|doc| {
            if &doc.collection_settings != expected {
                return Err("Collection settings changed. Reopen Settings to review them.".into());
            }
            settings.validate()?;
            doc.collection_settings = settings;
            Ok(())
        })
    }
    pub fn set_indicator_settings(
        &mut self,
        item: i64,
        view: i64,
        expected_parent: &IndicatorOverrides,
        expected_view: &IndicatorOverrides,
        parent: IndicatorOverrides,
        local: IndicatorOverrides,
    ) -> Result<(), String> {
        self.transact(|doc| {
            if !doc.items.contains_key(&item) {
                return Err("Item no longer exists.".into());
            }
            let saved_parent = doc
                .parent_indicator_defaults
                .get(&item)
                .cloned()
                .unwrap_or_default();
            let saved_view = doc
                .views
                .get(&view)
                .ok_or("View no longer exists.")?
                .preferences
                .get(&item)
                .map(|p| p.indicators.clone())
                .unwrap_or_default();
            if &saved_parent != expected_parent || &saved_view != expected_view {
                return Err(
                    "Indicator settings changed. Reopen their settings to review them.".into(),
                );
            }
            if parent.is_empty() {
                doc.parent_indicator_defaults.remove(&item);
            } else {
                doc.parent_indicator_defaults.insert(item, parent);
            }
            let prefs = &mut doc.views.get_mut(&view).unwrap().preferences;
            if !local.is_empty() || prefs.contains_key(&item) {
                prefs.entry(item).or_default().indicators = local;
            }
            Ok(())
        })
    }
    pub(crate) fn validate_settings(&self) -> Result<(), String> {
        self.collection_settings.validate()?;
        for id in self.parent_indicator_defaults.keys() {
            if !self.items.contains_key(id) {
                return Err("Indicator defaults refer to a missing item.".into());
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::ItemKind;
    #[test]
    fn inheritance_is_per_indicator_and_parent_not_ancestor_and_reset_is_live() {
        let mut doc = Document::new("settings".into());
        let parent = doc
            .add_item(ItemKind::Folder, "Parent".into(), None)
            .unwrap();
        let child = doc
            .add_item(ItemKind::Task, "Child".into(), Some(parent))
            .unwrap();
        let other = doc
            .add_view("Other".into(), crate::filter::FilterExpr::All)
            .unwrap();
        let empty = IndicatorOverrides::default();
        let shared = IndicatorOverrides {
            total: Some(false),
            ..empty.clone()
        };
        let local = IndicatorOverrides {
            high_priority: Some(false),
            ..empty.clone()
        };
        doc.set_indicator_settings(parent, 1, &empty, &empty, shared.clone(), local.clone())
            .unwrap();
        let old = doc.collection_settings.clone();
        let mut changed = old.clone();
        changed.indicators.next_due_date = true;
        doc.set_collection_settings(&old, changed).unwrap();
        assert!(!doc.resolved_indicators(parent, 1).unwrap().total);
        assert!(!doc.resolved_indicators(parent, 1).unwrap().high_priority);
        assert!(
            doc.resolved_indicators(parent, other)
                .unwrap()
                .high_priority
        );
        assert!(doc.resolved_indicators(parent, 1).unwrap().next_due_date);
        assert!(doc.resolved_indicators(child, 1).unwrap().total);
        doc.set_indicator_settings(parent, 1, &shared, &local, empty.clone(), empty.clone())
            .unwrap();
        assert_eq!(
            doc.resolved_indicators(parent, 1).unwrap(),
            doc.collection_settings.indicators
        );
        assert!(!doc.parent_indicator_defaults.contains_key(&parent));
    }
    #[test]
    fn stale_invalid_or_deleted_settings_are_atomic_and_removal_cleans_defaults() {
        let mut doc = Document::new("settings".into());
        let id = doc.add_item(ItemKind::Task, "Task".into(), None).unwrap();
        let old = doc.clone();
        let bad = CollectionSettings {
            tag_half_life_days: 0,
            ..Default::default()
        };
        assert!(doc
            .set_collection_settings(&CollectionSettings::default(), bad)
            .is_err());
        assert_eq!(doc, old);
        let empty = IndicatorOverrides::default();
        let local = IndicatorOverrides {
            total: Some(false),
            ..empty.clone()
        };
        doc.set_indicator_settings(id, 1, &empty, &empty, local.clone(), local)
            .unwrap();
        let saved = doc.clone();
        assert!(doc
            .set_indicator_settings(id, 1, &empty, &empty, empty.clone(), empty.clone())
            .is_err());
        assert_eq!(doc, saved);
        let removal = doc.preview_removal(id, None).unwrap();
        doc.remove_placement(&removal, true).unwrap();
        assert!(doc.parent_indicator_defaults.is_empty());
        doc.validate().unwrap();
    }
    #[test]
    fn absent_settings_preserve_legacy_serialized_document_and_receipts() {
        let doc = Document::new("legacy".into());
        let json = serde_json::to_value(&doc).unwrap();
        assert!(json.get("collection_settings").is_none());
        assert!(json.get("parent_indicator_defaults").is_none());
        assert_eq!(serde_json::from_value::<Document>(json).unwrap(), doc);
        assert!(serde_json::from_value::<CollectionSettings>(
            serde_json::json!({"tag_suggestion_count":-1})
        )
        .is_err());
        assert!(
            serde_json::from_value::<IndicatorOverrides>(serde_json::json!({"total":"yes"}))
                .is_err()
        );
    }
}
