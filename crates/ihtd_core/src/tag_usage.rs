//! Collection-owned manual tag-assignment history and time-decayed ranking.
use crate::model::Document;
use std::collections::BTreeMap;

/// UTC Unix seconds -> committed assignment count, grouped by tag. Keeping
/// actual history makes a changed half-life apply consistently to past usage.
pub type TagUsage = BTreeMap<i64, BTreeMap<i64, u64>>;

pub fn validate_time(now: i64) -> Result<(), String> {
    if !(0..=253_402_300_799).contains(&now) {
        return Err("Supply a valid UTC time for tag usage.".into());
    }
    Ok(())
}

impl Document {
    pub fn ranked_tags(&self, now: i64) -> Result<Vec<i64>, String> {
        validate_time(now)?;
        let half_life = f64::from(self.collection_settings.tag_half_life_days) * 86_400.0;
        let mut ranked: Vec<_> = self
            .tags
            .values()
            .map(|tag| {
                let score: f64 = self
                    .tag_usage
                    .get(&tag.id)
                    .into_iter()
                    .flat_map(|v| v.iter())
                    .map(|(&time, &count)| {
                        // A clock moving backward must not amplify an assignment.
                        let age = now.saturating_sub(time).max(0) as f64;
                        count as f64 * (-age / half_life).exp2()
                    })
                    .sum();
                (tag.id, score, tag.name.to_lowercase())
            })
            .collect();
        ranked.sort_by(|a, b| {
            b.1.total_cmp(&a.1)
                .then_with(|| a.2.cmp(&b.2))
                .then(a.0.cmp(&b.0))
        });
        Ok(ranked.into_iter().map(|(id, _, _)| id).collect())
    }

    pub fn record_tag_assignments(&mut self, ids: &[i64], now: i64) -> Result<(), String> {
        validate_time(now)?;
        self.transact(|doc| {
            for id in ids
                .iter()
                .copied()
                .collect::<std::collections::BTreeSet<_>>()
            {
                if !doc.tags.contains_key(&id) {
                    return Err("Assigned tag no longer exists.".into());
                }
                let count = doc.tag_usage.entry(id).or_default().entry(now).or_default();
                *count = count.checked_add(1).ok_or("Tag usage count exhausted")?;
            }
            Ok(())
        })
    }

    pub(crate) fn validate_tag_usage(&self) -> Result<(), String> {
        for (id, events) in &self.tag_usage {
            if !self.tags.contains_key(id) || events.is_empty() {
                return Err("Invalid tag usage history.".into());
            }
            for (&time, &count) in events {
                validate_time(time)?;
                if count == 0 {
                    return Err("Invalid tag usage count.".into());
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ranking_fades_with_current_half_life_and_old_collections_start_alphabetically() {
        let mut d = Document::new("tags".into());
        let z = d.add_tag("Zulu".into()).unwrap();
        let a = d.add_tag("alpha".into()).unwrap();
        let now = 1_800_000_000;
        assert_eq!(d.ranked_tags(now).unwrap(), [a, z]);
        for _ in 0..3 {
            d.record_tag_assignments(&[z], now).unwrap();
        }
        d.record_tag_assignments(&[a], now + 3 * 86_400).unwrap();
        assert_eq!(d.ranked_tags(now + 3 * 86_400).unwrap(), [z, a]);
        assert_eq!(d.ranked_tags(now + 6 * 86_400).unwrap(), [z, a]); // both fade, preserve ratio
        d.record_tag_assignments(&[a], now + 6 * 86_400).unwrap();
        assert_eq!(d.ranked_tags(now + 6 * 86_400).unwrap(), [a, z]);
        d.collection_settings.tag_half_life_days = 30;
        assert_eq!(d.ranked_tags(now + 6 * 86_400).unwrap(), [z, a]);
        assert_eq!(d.ranked_tags(now - 100).unwrap(), [z, a]); // no future amplification
    }
    #[test]
    fn assignments_are_atomic_deduplicated_and_deleted_tags_leave_no_dangling_history() {
        let mut d = Document::new("tags".into());
        let t = d.add_tag("Travel".into()).unwrap();
        d.record_tag_assignments(&[t, t], 100).unwrap();
        assert_eq!(d.tag_usage[&t][&100], 1);
        let before = d.clone();
        assert!(d.record_tag_assignments(&[t, 999], 200).is_err());
        assert!(d.ranked_tags(-1).is_err());
        assert_eq!(d, before);
        d.remove_tag(t).unwrap();
        assert!(d.tag_usage.is_empty());
        d.validate().unwrap();
    }
}
