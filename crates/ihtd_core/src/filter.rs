//! Saved-view predicates and deterministic suggestions for item creation.
//!
//! A suggestion is never authorization to create an item in a view: callers must
//! apply the proposed relationships and evaluate the full predicate afterward.
//! In particular, date ranges and Boolean alternatives often need user input.

use std::collections::{BTreeMap, BTreeSet};

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};

use crate::model::{Document, Item, ItemKind};

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TextField {
    Title,
    Notes,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TextComparison {
    Contains,
    Equals,
    StartsWith,
    EndsWith,
    NotContains,
    NotEquals,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DueComparison {
    Before,
    On,
    After,
    OnOrBefore,
    OnOrAfter,
    IsSet,
    IsNotSet,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PriorityComparison {
    Eq,
    Ge,
    Le,
}

fn default_recursive() -> bool {
    true
}

/// XOR means exactly one matching branch, including for groups with >2 rules.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum FilterExpr {
    #[default]
    All,
    And {
        rules: Vec<Self>,
    },
    Or {
        rules: Vec<Self>,
    },
    Xor {
        rules: Vec<Self>,
    },
    Not {
        rule: Box<Self>,
    },
    Text {
        field: TextField,
        comparison: TextComparison,
        value: String,
        #[serde(default)]
        case_sensitive: bool,
    },
    Tag {
        tag_id: i64,
    },
    /// Membership excludes the referenced item itself. The ID stays meaningful
    /// when a folder is converted to a task, so both container kinds are valid.
    Folder {
        folder_id: i64,
        #[serde(default = "default_recursive")]
        recursive: bool,
    },
    Due {
        comparison: DueComparison,
        #[serde(default)]
        value: Option<String>,
    },
    Priority {
        comparison: PriorityComparison,
        value: u8,
    },
    Kind {
        kind: ItemKind,
    },
    Completed {
        value: bool,
    },
}

/// Only determined values are filled. Requirements explain choices or conflicts
/// that still need attention; an empty list does not replace `matches` checking.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CreationDefaults {
    pub title: Option<String>,
    pub notes: Option<String>,
    pub due_date: Option<String>,
    pub priority: Option<u8>,
    pub tag_ids: Vec<i64>,
    pub kind: Option<ItemKind>,
    pub parent_ids: Vec<i64>,
    pub requirements: Vec<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ContainerRuleReference {
    pub path: String,
    pub container_id: i64,
}

impl FilterExpr {
    /// Human-readable rule positions, preserving nested group scope.
    pub fn container_rules(&self) -> Vec<ContainerRuleReference> {
        let mut result = vec![];
        let mut pending = vec![(self, "1".to_string())];
        while let Some((rule, path)) = pending.pop() {
            match rule {
                Self::Folder { folder_id, .. } => result.push(ContainerRuleReference {
                    path,
                    container_id: *folder_id,
                }),
                Self::And { rules } | Self::Or { rules } | Self::Xor { rules } => {
                    for (index, child) in rules.iter().enumerate().rev() {
                        pending.push((child, format!("{path}.{}", index + 1)));
                    }
                }
                Self::Not { rule } => pending.push((rule, format!("{path}.1"))),
                _ => (),
            }
        }
        result
    }

    pub fn deleted_container_rules(&self, document: &Document) -> Vec<ContainerRuleReference> {
        self.container_rules()
            .into_iter()
            .filter(|r| document.deleted_item_ids.contains(&r.container_id))
            .collect()
    }

    pub fn matches(&self, item: &Item, document: &Document) -> bool {
        match self {
            Self::All => true,
            Self::And { rules } => rules.iter().all(|rule| rule.matches(item, document)),
            Self::Or { rules } => rules.iter().any(|rule| rule.matches(item, document)),
            Self::Xor { rules } => {
                rules
                    .iter()
                    .filter(|rule| rule.matches(item, document))
                    .take(2)
                    .count()
                    == 1
            }
            Self::Not { rule } => !rule.matches(item, document),
            Self::Text {
                field,
                comparison,
                value,
                case_sensitive,
            } => {
                let actual = match field {
                    TextField::Title => &item.title,
                    TextField::Notes => &item.notes,
                };
                text_matches(actual, *comparison, value, *case_sensitive)
            }
            Self::Tag { tag_id } => item.tag_ids.contains(tag_id),
            Self::Folder {
                folder_id,
                recursive,
            } => is_in_container(item.id, *folder_id, *recursive, document),
            Self::Due { comparison, value } => {
                due_matches(item.due_date.as_deref(), *comparison, value.as_deref())
            }
            Self::Priority { comparison, value } => {
                priority_matches(item.priority, *comparison, *value)
            }
            Self::Kind { kind } => item.kind == *kind,
            Self::Completed { value } => item.kind == ItemKind::Task && item.completed == *value,
        }
    }

    /// Check expression shape, referenced IDs, and field values. Logical
    /// contradictions are allowed as saved filters (they simply match nothing).
    pub fn validate(&self, document: &Document) -> Result<(), String> {
        let mut pending = vec![self];
        while let Some(rule) = pending.pop() {
            match rule {
                Self::And { rules } | Self::Or { rules } | Self::Xor { rules } => {
                    if rules.is_empty() {
                        return Err("A filter group must contain at least one rule".into());
                    }
                    pending.extend(rules);
                }
                Self::Not { rule } => pending.push(rule),
                Self::Tag { tag_id } if !document.tags.contains_key(tag_id) => {
                    return Err(format!("Filter references missing tag #{tag_id}"));
                }
                Self::Folder { folder_id, .. }
                    if !document.items.contains_key(folder_id)
                        && !document.deleted_item_ids.contains(folder_id) =>
                {
                    return Err(format!("Filter references missing container #{folder_id}"));
                }
                Self::Due { comparison, value } => match comparison {
                    DueComparison::IsSet | DueComparison::IsNotSet => {
                        if value.is_some() {
                            return Err("Due-date presence rules must not contain a date".into());
                        }
                    }
                    _ => {
                        let value = value
                            .as_deref()
                            .ok_or("This due-date comparison needs a date")?;
                        if parse_date(value).is_none() {
                            return Err(format!("Invalid due date '{value}'; use YYYY-MM-DD"));
                        }
                    }
                },
                Self::Priority { value, .. } if *value > 3 => {
                    return Err(
                        "Priority must be None (0), Low (1), Medium (2), or High (3)".into(),
                    );
                }
                _ => {}
            }
        }
        Ok(())
    }

    pub fn creation_defaults(&self, document: &Document) -> CreationDefaults {
        if let Err(error) = self.validate(document) {
            return CreationDefaults {
                requirements: vec![error],
                ..CreationDefaults::default()
            };
        }
        let mut defaults = self.hints().resolve();
        defaults
            .parent_ids
            .retain(|id| document.items.contains_key(id));
        for reference in self.deleted_container_rules(document) {
            defaults.requirements.push(format!(
                "Rule {} refers to deleted container #{}. Replace or remove this rule.",
                reference.path, reference.container_id
            ));
        }
        defaults.requirements.sort();
        defaults.requirements.dedup();
        defaults
    }

    fn hints(&self) -> Hints {
        let mut hints = Hints::default();
        match self {
            Self::All => {}
            Self::And { rules } => {
                for rule in rules {
                    hints.merge(rule.hints());
                }
            }
            Self::Or { rules } => {
                // The user explicitly chose all tags for a simple tag OR.
                if let Some(ids) = tag_alternatives(rules) {
                    hints.tags.extend(ids);
                } else {
                    hints = common_hints(rules);
                    hints
                        .requirements
                        .push("Choose values satisfying at least one OR alternative".into());
                }
            }
            Self::Xor { rules } => {
                if let Some(ids) = tag_alternatives(rules) {
                    // Repeating a tag in two alternatives cannot satisfy exactly
                    // one branch. Choose the lowest ID occurring only once.
                    let mut counts = BTreeMap::new();
                    for id in ids {
                        *counts.entry(id).or_insert(0_usize) += 1;
                    }
                    if let Some((&id, _)) = counts.iter().find(|(_, count)| **count == 1) {
                        hints.tags.insert(id);
                        hints
                            .forbidden_tags
                            .extend(counts.keys().copied().filter(|other| *other != id));
                    } else {
                        hints.requirements.push(
                            "These XOR tag alternatives cannot match exactly one branch".into(),
                        );
                    }
                } else {
                    hints = common_hints(rules);
                    hints
                        .requirements
                        .push("Choose values satisfying exactly one XOR alternative".into());
                }
            }
            Self::Not { rule } => match rule.as_ref() {
                Self::Not { rule } => return rule.hints(),
                Self::Tag { tag_id } => {
                    hints.forbidden_tags.insert(*tag_id);
                }
                Self::Text {
                    field,
                    comparison,
                    value,
                    case_sensitive,
                } => {
                    let inverse = match comparison {
                        TextComparison::Contains => Some(TextComparison::NotContains),
                        TextComparison::NotContains => Some(TextComparison::Contains),
                        TextComparison::Equals => Some(TextComparison::NotEquals),
                        TextComparison::NotEquals => Some(TextComparison::Equals),
                        _ => None,
                    };
                    if let Some(comparison) = inverse {
                        hints.text(*field).push(TextRule {
                            comparison,
                            value: value.clone(),
                            case_sensitive: *case_sensitive,
                        });
                    } else {
                        hints
                            .requirements
                            .push("The entered text must satisfy the NOT rule".into());
                    }
                }
                Self::All => hints
                    .requirements
                    .push("NOT All cannot match any item".into()),
                _ => hints
                    .requirements
                    .push("Choose values satisfying the NOT rule".into()),
            },
            Self::Text {
                field,
                comparison,
                value,
                case_sensitive,
            } => {
                hints.text(*field).push(TextRule {
                    comparison: *comparison,
                    value: value.clone(),
                    case_sensitive: *case_sensitive,
                });
            }
            Self::Tag { tag_id } => {
                hints.tags.insert(*tag_id);
            }
            Self::Folder { folder_id, .. } => {
                hints.parents.insert(*folder_id);
            }
            Self::Due { comparison, value } => hints.dates.push((*comparison, value.clone())),
            Self::Priority { comparison, value } => hints.priorities.push((*comparison, *value)),
            Self::Kind { kind } => hints.kinds.push(*kind),
            Self::Completed { value: true } => {
                hints
                    .requirements
                    .push("This view requires a completed task".into());
                hints.kinds.push(ItemKind::Task);
            }
            Self::Completed { value: false } => hints.kinds.push(ItemKind::Task),
        }
        hints
    }
}

fn text_matches(
    actual: &str,
    comparison: TextComparison,
    value: &str,
    case_sensitive: bool,
) -> bool {
    let normalized_actual;
    let normalized_value;
    let (actual, value) = if case_sensitive {
        (actual, value)
    } else {
        normalized_actual = actual.to_lowercase();
        normalized_value = value.to_lowercase();
        (normalized_actual.as_str(), normalized_value.as_str())
    };
    match comparison {
        TextComparison::Contains => actual.contains(value),
        TextComparison::Equals => actual == value,
        TextComparison::StartsWith => actual.starts_with(value),
        TextComparison::EndsWith => actual.ends_with(value),
        TextComparison::NotContains => !actual.contains(value),
        TextComparison::NotEquals => actual != value,
    }
}

fn parse_date(value: &str) -> Option<NaiveDate> {
    if value.len() != 10
        || value.as_bytes().get(4) != Some(&b'-')
        || value.as_bytes().get(7) != Some(&b'-')
    {
        return None;
    }
    NaiveDate::parse_from_str(value, "%Y-%m-%d").ok()
}

fn due_matches(actual: Option<&str>, comparison: DueComparison, value: Option<&str>) -> bool {
    match comparison {
        DueComparison::IsSet => actual.and_then(parse_date).is_some(),
        DueComparison::IsNotSet => actual.is_none(),
        _ => {
            let (Some(actual), Some(value)) =
                (actual.and_then(parse_date), value.and_then(parse_date))
            else {
                return false;
            };
            match comparison {
                DueComparison::Before => actual < value,
                DueComparison::On => actual == value,
                DueComparison::After => actual > value,
                DueComparison::OnOrBefore => actual <= value,
                DueComparison::OnOrAfter => actual >= value,
                _ => unreachable!(),
            }
        }
    }
}

fn priority_matches(actual: u8, comparison: PriorityComparison, value: u8) -> bool {
    if actual > 3 || value > 3 {
        return false;
    }
    match comparison {
        PriorityComparison::Eq => actual == value,
        PriorityComparison::Ge => actual >= value,
        PriorityComparison::Le => actual <= value,
    }
}

fn is_in_container(item_id: i64, container_id: i64, recursive: bool, document: &Document) -> bool {
    if item_id == container_id {
        return false;
    }
    if !recursive {
        return document
            .links
            .iter()
            .any(|link| link.parent == container_id && link.child == item_id);
    }
    let mut parents: BTreeMap<i64, Vec<i64>> = BTreeMap::new();
    for link in &document.links {
        parents.entry(link.child).or_default().push(link.parent);
    }
    let mut visited = BTreeSet::from([item_id]);
    let mut pending = vec![item_id];
    while let Some(current) = pending.pop() {
        for &parent in parents.get(&current).into_iter().flatten() {
            if parent == container_id {
                return true;
            }
            if visited.insert(parent) {
                pending.push(parent);
            }
        }
    }
    false
}

#[derive(Default)]
struct Hints {
    title: Vec<TextRule>,
    notes: Vec<TextRule>,
    dates: Vec<(DueComparison, Option<String>)>,
    priorities: Vec<(PriorityComparison, u8)>,
    kinds: Vec<ItemKind>,
    tags: BTreeSet<i64>,
    forbidden_tags: BTreeSet<i64>,
    parents: BTreeSet<i64>,
    requirements: Vec<String>,
}

struct TextRule {
    comparison: TextComparison,
    value: String,
    case_sensitive: bool,
}

impl Hints {
    fn text(&mut self, field: TextField) -> &mut Vec<TextRule> {
        match field {
            TextField::Title => &mut self.title,
            TextField::Notes => &mut self.notes,
        }
    }

    fn merge(&mut self, other: Self) {
        self.title.extend(other.title);
        self.notes.extend(other.notes);
        self.dates.extend(other.dates);
        self.priorities.extend(other.priorities);
        self.kinds.extend(other.kinds);
        self.tags.extend(other.tags);
        self.forbidden_tags.extend(other.forbidden_tags);
        self.parents.extend(other.parents);
        self.requirements.extend(other.requirements);
    }

    fn resolve(mut self) -> CreationDefaults {
        let title = resolve_text("Title", &self.title, &mut self.requirements);
        let notes = resolve_text("Notes", &self.notes, &mut self.requirements);
        let due_date = self.dates.iter().find_map(|(comparison, value)| {
            (*comparison == DueComparison::On)
                .then_some(value.clone())
                .flatten()
        });
        if let Some(ref date) = due_date {
            if self
                .dates
                .iter()
                .any(|(comparison, value)| !due_matches(Some(date), *comparison, value.as_deref()))
            {
                self.requirements
                    .push("The due-date conditions conflict; no date can satisfy them".into());
            }
        } else if self
            .dates
            .iter()
            .any(|(comparison, _)| *comparison != DueComparison::IsNotSet)
        {
            self.requirements
                .push("Choose a due date satisfying the view's date conditions".into());
        }
        let priority = if self.priorities.is_empty() {
            None
        } else {
            let allowed: Vec<_> = (0..=3)
                .filter(|actual| {
                    self.priorities
                        .iter()
                        .all(|(comparison, value)| priority_matches(*actual, *comparison, *value))
                })
                .collect();
            match allowed.as_slice() {
                [only] => Some(*only),
                [] => {
                    self.requirements.push(
                        "The priority conditions conflict; no priority can satisfy them".into(),
                    );
                    None
                }
                _ => {
                    self.requirements
                        .push("Choose a priority satisfying the view's priority conditions".into());
                    None
                }
            }
        };
        let kind = self.kinds.first().copied();
        if self.kinds.iter().any(|candidate| Some(*candidate) != kind) {
            self.requirements
                .push("The kind conditions require both a task and a folder".into());
        }
        for tag in self.tags.intersection(&self.forbidden_tags) {
            self.requirements.push(format!("Tag #{tag} is both required and excluded by the creation suggestions; adjust the choices to satisfy the complete filter"));
        }
        CreationDefaults {
            title,
            notes,
            due_date,
            priority,
            tag_ids: self.tags.into_iter().collect(),
            kind,
            parent_ids: self.parents.into_iter().collect(),
            requirements: self.requirements,
        }
    }
}

fn resolve_text(label: &str, rules: &[TextRule], requirements: &mut Vec<String>) -> Option<String> {
    let mut suggested = if let Some(rule) = rules
        .iter()
        .find(|rule| rule.comparison == TextComparison::Equals)
    {
        Some(rule.value.clone())
    } else {
        let prefix = rules
            .iter()
            .filter(|rule| rule.comparison == TextComparison::StartsWith)
            .max_by_key(|rule| rule.value.len());
        let suffix = rules
            .iter()
            .filter(|rule| rule.comparison == TextComparison::EndsWith)
            .max_by_key(|rule| rule.value.len());
        let mut value = prefix.map(|rule| rule.value.clone());
        for rule in rules
            .iter()
            .filter(|rule| rule.comparison == TextComparison::Contains)
        {
            let value = value.get_or_insert_with(String::new);
            if !text_matches(
                value,
                TextComparison::Contains,
                &rule.value,
                rule.case_sensitive,
            ) {
                append_words(value, &rule.value);
            }
        }
        if let Some(suffix) = suffix {
            let value = value.get_or_insert_with(String::new);
            if !text_matches(
                value,
                TextComparison::EndsWith,
                &suffix.value,
                suffix.case_sensitive,
            ) {
                append_words(value, &suffix.value);
            }
        }
        value
    };
    if let Some(value) = &suggested {
        if rules
            .iter()
            .any(|rule| !text_matches(value, rule.comparison, &rule.value, rule.case_sensitive))
        {
            requirements.push(format!("Adjust {label} to satisfy all text conditions; the literal suggestions do not satisfy them together"));
        }
    } else if rules
        .iter()
        .any(|rule| !text_matches("", rule.comparison, &rule.value, rule.case_sensitive))
    {
        requirements.push(format!("Enter {label} satisfying the text conditions"));
    }
    // An explicit empty literal remains a determined value. The item model can
    // still reject an empty title when the user submits the creation form.
    suggested.take()
}

fn append_words(target: &mut String, value: &str) {
    if !target.is_empty() && !value.is_empty() {
        target.push(' ');
    }
    target.push_str(value);
}

fn tag_alternatives(rules: &[FilterExpr]) -> Option<Vec<i64>> {
    rules
        .iter()
        .map(|rule| match rule {
            FilterExpr::Tag { tag_id } => Some(*tag_id),
            _ => None,
        })
        .collect()
}

/// Preserve only values common to all nontrivial alternatives. This avoids
/// choosing an arbitrary date, title, folder, or priority for the user.
fn common_hints(rules: &[FilterExpr]) -> Hints {
    let suggestions: Vec<_> = rules.iter().map(|rule| rule.hints().resolve()).collect();
    let mut hints = Hints::default();
    let Some(first) = suggestions.first() else {
        return hints;
    };
    if let Some(title) = &first.title {
        if suggestions
            .iter()
            .all(|other| other.title.as_ref() == Some(title))
        {
            hints.title.push(TextRule {
                comparison: TextComparison::Contains,
                value: title.clone(),
                case_sensitive: true,
            });
        }
    }
    if let Some(notes) = &first.notes {
        if suggestions
            .iter()
            .all(|other| other.notes.as_ref() == Some(notes))
        {
            hints.notes.push(TextRule {
                comparison: TextComparison::Contains,
                value: notes.clone(),
                case_sensitive: true,
            });
        }
    }
    if let Some(date) = &first.due_date {
        if suggestions
            .iter()
            .all(|other| other.due_date.as_ref() == Some(date))
        {
            hints.dates.push((DueComparison::On, Some(date.clone())));
        }
    }
    if let Some(priority) = first.priority {
        if suggestions
            .iter()
            .all(|other| other.priority == Some(priority))
        {
            hints.priorities.push((PriorityComparison::Eq, priority));
        }
    }
    if let Some(kind) = first.kind {
        if suggestions.iter().all(|other| other.kind == Some(kind)) {
            hints.kinds.push(kind);
        }
    }
    hints.tags.extend(
        first
            .tag_ids
            .iter()
            .filter(|id| suggestions.iter().all(|other| other.tag_ids.contains(id)))
            .copied(),
    );
    hints.parents.extend(
        first
            .parent_ids
            .iter()
            .filter(|id| {
                suggestions
                    .iter()
                    .all(|other| other.parent_ids.contains(id))
            })
            .copied(),
    );
    hints
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Link, Tag};

    fn fixture() -> Document {
        let mut document = Document::new("filter-tests".into());
        document.tags.insert(
            20,
            Tag {
                id: 20,
                name: "Work".into(),
            },
        );
        document.tags.insert(
            30,
            Tag {
                id: 30,
                name: "Personal".into(),
            },
        );
        document.tags.insert(
            40,
            Tag {
                id: 40,
                name: "Travel".into(),
            },
        );
        document.next_id = 100;
        document
    }

    fn task() -> Item {
        Item::new(50, ItemKind::Task, "Prepare invoice 2026".into())
    }

    fn text(field: TextField, comparison: TextComparison, value: &str) -> FilterExpr {
        FilterExpr::Text {
            field,
            comparison,
            value: value.into(),
            case_sensitive: false,
        }
    }

    fn date(comparison: DueComparison, value: &str) -> FilterExpr {
        FilterExpr::Due {
            comparison,
            value: Some(value.into()),
        }
    }

    fn candidate(defaults: &CreationDefaults, document: &mut Document) -> Item {
        let mut item = task();
        if let Some(value) = &defaults.title {
            item.title = value.clone();
        }
        if let Some(value) = &defaults.notes {
            item.notes = value.clone();
        }
        if let Some(value) = &defaults.due_date {
            item.due_date = Some(value.clone());
        }
        if let Some(value) = defaults.priority {
            item.priority = value;
        }
        if let Some(value) = defaults.kind {
            item.kind = value;
        }
        item.tag_ids = defaults.tag_ids.clone();
        for &parent in &defaults.parent_ids {
            document.links.push(Link {
                parent,
                child: item.id,
            });
        }
        item
    }

    #[test]
    fn boolean_groups_handle_all_truth_combinations_and_xor_means_exactly_one() {
        let document = fixture();
        let rules = vec![
            FilterExpr::Tag { tag_id: 20 },
            FilterExpr::Tag { tag_id: 30 },
            FilterExpr::Tag { tag_id: 40 },
        ];
        let and = FilterExpr::And {
            rules: rules.clone(),
        };
        let or = FilterExpr::Or {
            rules: rules.clone(),
        };
        let xor = FilterExpr::Xor { rules };
        let not = FilterExpr::Not {
            rule: Box::new(xor.clone()),
        };
        for mask in 0_u32..8 {
            let mut item = task();
            item.tag_ids = [20, 30, 40]
                .into_iter()
                .enumerate()
                .filter_map(|(bit, id)| ((mask & (1 << bit)) != 0).then_some(id))
                .collect();
            assert_eq!(and.matches(&item, &document), mask == 7);
            assert_eq!(or.matches(&item, &document), mask != 0);
            assert_eq!(xor.matches(&item, &document), mask.count_ones() == 1);
            assert_eq!(not.matches(&item, &document), mask.count_ones() != 1);
        }
    }

    #[test]
    fn nested_boolean_filters_combine_text_tags_and_negation() {
        let document = fixture();
        let expression = FilterExpr::And {
            rules: vec![
                FilterExpr::Or {
                    rules: vec![
                        FilterExpr::Tag { tag_id: 20 },
                        FilterExpr::Tag { tag_id: 30 },
                    ],
                },
                text(TextField::Title, TextComparison::Contains, "2026"),
                FilterExpr::Not {
                    rule: Box::new(text(
                        TextField::Notes,
                        TextComparison::Contains,
                        "cancelled",
                    )),
                },
            ],
        };
        let mut item = task();
        item.tag_ids = vec![20];
        assert!(expression.matches(&item, &document));
        item.notes = "CANCELLED yesterday".into();
        assert!(!expression.matches(&item, &document));
        item.notes.clear();
        item.tag_ids.clear();
        assert!(!expression.matches(&item, &document));
    }

    #[test]
    fn text_predicates_cover_notes_numbers_unicode_and_case() {
        let document = fixture();
        let mut item = task();
        item.notes = "Äpfel and invoice 2026".into();
        for (comparison, value, expected) in [
            (TextComparison::Contains, "INVOICE 2026", true),
            (TextComparison::Equals, "äpfel and invoice 2026", true),
            (TextComparison::StartsWith, "äpfel", true),
            (TextComparison::EndsWith, "2026", true),
            (TextComparison::NotContains, "2026", false),
            (TextComparison::NotEquals, "other", true),
        ] {
            assert_eq!(
                text(TextField::Notes, comparison, value).matches(&item, &document),
                expected
            );
        }
        let sensitive = FilterExpr::Text {
            field: TextField::Notes,
            comparison: TextComparison::Contains,
            value: "INVOICE".into(),
            case_sensitive: true,
        };
        assert!(!sensitive.matches(&item, &document));
        assert!(text(TextField::Title, TextComparison::Contains, "2026").matches(&item, &document));
    }

    #[test]
    fn dates_are_real_calendar_dates_and_absent_dates_fail_ordered_comparisons() {
        let document = fixture();
        let mut item = task();
        let on = date(DueComparison::On, "2026-09-29");
        let absent = FilterExpr::Due {
            comparison: DueComparison::IsNotSet,
            value: None,
        };
        assert!(!on.matches(&item, &document));
        assert!(absent.matches(&item, &document));
        item.due_date = Some("2026-09-29".into());
        assert!(on.matches(&item, &document));
        assert!(date(DueComparison::Before, "2026-09-30").matches(&item, &document));
        assert!(date(DueComparison::After, "2026-09-28").matches(&item, &document));
        assert!(date(DueComparison::OnOrBefore, "2026-09-29").matches(&item, &document));
        assert!(date(DueComparison::OnOrAfter, "2026-09-29").matches(&item, &document));
        assert!(!date(DueComparison::Before, "2026-09-29").matches(&item, &document));
        for bad in ["2026-02-30", "2026-2-03", "2026/09/29", "yesterday"] {
            assert!(date(DueComparison::On, bad).validate(&document).is_err());
        }
        assert!(date(DueComparison::On, "2028-02-29")
            .validate(&document)
            .is_ok());
        assert!(FilterExpr::Due {
            comparison: DueComparison::Before,
            value: None
        }
        .validate(&document)
        .is_err());
    }

    #[test]
    fn priority_kind_and_completion_have_typed_semantics() {
        let document = fixture();
        let mut item = task();
        item.priority = 2;
        assert!(FilterExpr::Priority {
            comparison: PriorityComparison::Ge,
            value: 1
        }
        .matches(&item, &document));
        assert!(!FilterExpr::Priority {
            comparison: PriorityComparison::Le,
            value: 1
        }
        .matches(&item, &document));
        assert!(FilterExpr::Priority {
            comparison: PriorityComparison::Eq,
            value: 2
        }
        .matches(&item, &document));
        assert!(FilterExpr::Completed { value: false }.matches(&item, &document));
        item.kind = ItemKind::Folder;
        assert!(FilterExpr::Kind {
            kind: ItemKind::Folder
        }
        .matches(&item, &document));
        assert!(!FilterExpr::Completed { value: false }.matches(&item, &document));
    }

    #[test]
    fn folder_membership_follows_all_shared_paths_and_survives_conversion() {
        let mut document = fixture();
        for (id, kind) in [
            (2, ItemKind::Folder),
            (3, ItemKind::Folder),
            (4, ItemKind::Task),
            (5, ItemKind::Task),
        ] {
            document
                .items
                .insert(id, Item::new(id, kind, format!("Item {id}")));
        }
        for (parent, child) in [(2, 4), (3, 4), (4, 5)] {
            document.links.push(Link { parent, child });
        }
        for folder_id in [2, 3] {
            let recursive = FilterExpr::Folder {
                folder_id,
                recursive: true,
            };
            let direct = FilterExpr::Folder {
                folder_id,
                recursive: false,
            };
            assert!(recursive.matches(&document.items[&5], &document));
            assert!(!direct.matches(&document.items[&5], &document));
            assert!(direct.matches(&document.items[&4], &document));
            assert!(!recursive.matches(&document.items[&folder_id], &document));
        }
        document.items.get_mut(&2).unwrap().kind = ItemKind::Task;
        let converted = FilterExpr::Folder {
            folder_id: 2,
            recursive: true,
        };
        assert!(converted.validate(&document).is_ok());
        assert!(converted.matches(&document.items[&5], &document));
    }

    #[test]
    fn deep_container_membership_is_iterative() {
        let mut document = fixture();
        for id in 2..=20_002 {
            document
                .items
                .insert(id, Item::new(id, ItemKind::Task, format!("Item {id}")));
            if id > 2 {
                document.links.push(Link {
                    parent: id - 1,
                    child: id,
                });
            }
        }
        let filter = FilterExpr::Folder {
            folder_id: 2,
            recursive: true,
        };
        assert!(filter.matches(&document.items[&20_002], &document));
    }

    #[test]
    fn creation_prefills_both_or_tags_and_note_literal_but_requires_range_date() {
        let mut document = fixture();
        let expression = FilterExpr::And {
            rules: vec![
                FilterExpr::Or {
                    rules: vec![
                        FilterExpr::Tag { tag_id: 30 },
                        FilterExpr::Tag { tag_id: 20 },
                    ],
                },
                text(TextField::Notes, TextComparison::Contains, "invoice"),
                date(DueComparison::Before, "2026-10-02"),
            ],
        };
        let defaults = expression.creation_defaults(&document);
        assert_eq!(defaults.tag_ids, [20, 30]);
        assert_eq!(defaults.notes.as_deref(), Some("invoice"));
        assert_eq!(defaults.due_date, None);
        assert!(defaults
            .requirements
            .iter()
            .any(|message| message.contains("Choose a due date")));
        let mut item = candidate(&defaults, &mut document);
        assert!(!expression.matches(&item, &document));
        item.due_date = Some("2026-10-01".into());
        assert!(expression.matches(&item, &document));
    }

    #[test]
    fn xor_prefill_chooses_lowest_tag_id_and_exactly_one_match() {
        let mut document = fixture();
        let expression = FilterExpr::Xor {
            rules: vec![
                FilterExpr::Tag { tag_id: 30 },
                FilterExpr::Tag { tag_id: 20 },
            ],
        };
        let defaults = expression.creation_defaults(&document);
        assert_eq!(defaults.tag_ids, [20]);
        assert!(defaults.requirements.is_empty());
        let mut item = candidate(&defaults, &mut document);
        assert!(expression.matches(&item, &document));
        item.tag_ids.push(30);
        assert!(!expression.matches(&item, &document));
    }

    #[test]
    fn prefills_combine_text_constraints_exact_dates_priorities_and_placements() {
        let mut document = fixture();
        document
            .items
            .insert(2, Item::new(2, ItemKind::Folder, "Work".into()));
        let expression = FilterExpr::And {
            rules: vec![
                text(TextField::Title, TextComparison::StartsWith, "Submit"),
                text(TextField::Title, TextComparison::Contains, "invoice"),
                text(TextField::Title, TextComparison::EndsWith, "2026"),
                date(DueComparison::On, "2026-09-29"),
                FilterExpr::Priority {
                    comparison: PriorityComparison::Ge,
                    value: 3,
                },
                FilterExpr::Folder {
                    folder_id: 2,
                    recursive: true,
                },
                FilterExpr::Kind {
                    kind: ItemKind::Task,
                },
            ],
        };
        let defaults = expression.creation_defaults(&document);
        assert_eq!(defaults.title.as_deref(), Some("Submit invoice 2026"));
        assert_eq!(defaults.due_date.as_deref(), Some("2026-09-29"));
        assert_eq!(defaults.priority, Some(3));
        assert_eq!(defaults.parent_ids, [2]);
        assert!(defaults.requirements.is_empty());
        let item = candidate(&defaults, &mut document);
        assert!(expression.matches(&item, &document));
    }

    #[test]
    fn unsatisfiable_conditions_are_not_claimed_as_complete_creation() {
        let mut document = fixture();
        let impossible = FilterExpr::And {
            rules: vec![
                date(DueComparison::On, "2026-09-29"),
                date(DueComparison::Before, "2026-09-29"),
                FilterExpr::Priority {
                    comparison: PriorityComparison::Ge,
                    value: 3,
                },
                FilterExpr::Priority {
                    comparison: PriorityComparison::Le,
                    value: 1,
                },
                FilterExpr::Tag { tag_id: 20 },
                FilterExpr::Not {
                    rule: Box::new(FilterExpr::Tag { tag_id: 20 }),
                },
            ],
        };
        let defaults = impossible.creation_defaults(&document);
        assert!(defaults.requirements.len() >= 3);
        let item = candidate(&defaults, &mut document);
        assert!(!impossible.matches(&item, &document));
        let not_all = FilterExpr::Not {
            rule: Box::new(FilterExpr::All),
        };
        assert!(!not_all.creation_defaults(&document).requirements.is_empty());
        assert!(!not_all.matches(&item, &document));
    }

    #[test]
    fn ambiguous_boolean_alternatives_do_not_choose_a_date_or_title() {
        let document = fixture();
        let expression = FilterExpr::Or {
            rules: vec![
                FilterExpr::And {
                    rules: vec![
                        text(TextField::Title, TextComparison::Equals, "A"),
                        date(DueComparison::On, "2026-09-29"),
                    ],
                },
                FilterExpr::And {
                    rules: vec![
                        text(TextField::Title, TextComparison::Equals, "B"),
                        date(DueComparison::On, "2026-09-30"),
                    ],
                },
            ],
        };
        let defaults = expression.creation_defaults(&document);
        assert_eq!(defaults.title, None);
        assert_eq!(defaults.due_date, None);
        assert!(!defaults.requirements.is_empty());
    }

    #[test]
    fn double_negation_prefills_literals_and_negative_text_does_not_invent_a_title() {
        let document = fixture();
        let positive = FilterExpr::Not {
            rule: Box::new(FilterExpr::Not {
                rule: Box::new(FilterExpr::Tag { tag_id: 20 }),
            }),
        };
        assert_eq!(positive.creation_defaults(&document).tag_ids, [20]);
        let negative = text(TextField::Title, TextComparison::NotContains, "invoice");
        assert_eq!(negative.creation_defaults(&document).title, None);
    }

    #[test]
    fn invalid_references_or_shapes_are_rejected_before_prefill() {
        let document = fixture();
        for expression in [
            FilterExpr::Tag { tag_id: 999 },
            FilterExpr::Folder {
                folder_id: 999,
                recursive: true,
            },
            FilterExpr::And { rules: vec![] },
            FilterExpr::Or { rules: vec![] },
            FilterExpr::Xor { rules: vec![] },
            FilterExpr::Priority {
                comparison: PriorityComparison::Eq,
                value: 4,
            },
        ] {
            assert!(expression.validate(&document).is_err());
            assert!(!expression
                .creation_defaults(&document)
                .requirements
                .is_empty());
        }
    }

    #[test]
    fn json_contract_uses_tagged_predicates_and_backward_compatible_defaults() {
        let insensitive: FilterExpr = serde_json::from_str(
            r#"{"op":"text","field":"notes","comparison":"contains","value":"Invoice"}"#,
        )
        .unwrap();
        assert_eq!(
            insensitive,
            text(TextField::Notes, TextComparison::Contains, "Invoice")
        );
        let folder: FilterExpr = serde_json::from_str(r#"{"op":"folder","folder_id":2}"#).unwrap();
        assert_eq!(
            folder,
            FilterExpr::Folder {
                folder_id: 2,
                recursive: true
            }
        );
        let encoded = serde_json::to_value(FilterExpr::And {
            rules: vec![insensitive, folder],
        })
        .unwrap();
        assert_eq!(encoded["op"], "and");
        assert_eq!(encoded["rules"][0]["case_sensitive"], false);
        assert_eq!(encoded["rules"][1]["recursive"], true);
    }
}
