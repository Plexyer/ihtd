//! Ordered task and folder placements in a directed acyclic graph.
//!
//! An item has one identity and one ordered list of children, regardless of how
//! many parents reference it. Titles are intentionally outside this module:
//! identical titles do not imply identical items. Every traversal is iterative.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fmt;

/// A stable, positive document-local identifier compatible with SQLite integers.
///
/// Allocation and persistence belong to the storage layer. IDs from different
/// documents must never be combined in one graph.
#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
pub struct ItemId(i64);

impl ItemId {
    pub fn new(value: i64) -> Result<Self, GraphError> {
        if value <= 0 {
            return Err(GraphError::InvalidItemId(value));
        }
        Ok(Self(value))
    }

    pub fn get(self) -> i64 {
        self.0
    }
}

impl fmt::Display for ItemId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ItemKind {
    Task,
    Folder,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum GraphError {
    InvalidItemId(i64),
    MissingItem(ItemId),
    DuplicateItem(ItemId),
    DuplicateLink { parent: ItemId, child: ItemId },
    MissingLink { parent: ItemId, child: ItemId },
    Cycle { parent: ItemId, child: ItemId },
    InvariantViolation { item: ItemId, reason: &'static str },
}

impl fmt::Display for GraphError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidItemId(id) => write!(f, "Item ID must be positive, received {id}"),
            Self::MissingItem(id) => write!(f, "Item {id} does not exist"),
            Self::DuplicateItem(id) => write!(f, "Item {id} already exists"),
            Self::DuplicateLink { parent, child } => {
                write!(f, "Item {child} is already a child of item {parent}")
            }
            Self::MissingLink { parent, child } => {
                write!(f, "Item {child} is not a child of item {parent}")
            }
            Self::Cycle { parent, child } => {
                write!(
                    f,
                    "Making item {child} a child of item {parent} would create a cycle"
                )
            }
            Self::InvariantViolation { item, reason } => {
                write!(f, "Invalid graph at item {item}: {reason}")
            }
        }
    }
}

impl std::error::Error for GraphError {}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Node {
    kind: ItemKind,
    children: Vec<ItemId>,
    parents: BTreeSet<ItemId>,
}

/// Items and their shared placements, with cycles and duplicate links rejected.
///
/// Child order is insertion order; parent and root order is ascending ID. A
/// failed mutation leaves the graph unchanged. There is no fixed depth limit.
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Graph {
    nodes: BTreeMap<ItemId, Node>,
}

impl Graph {
    pub fn new() -> Self {
        Self::default()
    }

    /// Build imported graphs in one pass, then reject cycles. Unlike repeated
    /// `link` calls, this does not traverse the graph for every imported edge.
    pub fn from_parts(
        items: impl IntoIterator<Item = (ItemId, ItemKind)>,
        links: impl IntoIterator<Item = (ItemId, ItemId)>,
    ) -> Result<Self, GraphError> {
        let mut graph = Self::new();
        for (id, kind) in items {
            graph.add_item(id, kind)?;
        }
        for (parent, child) in links {
            graph.node(parent)?;
            graph.node(child)?;
            if !graph.nodes.get_mut(&child).unwrap().parents.insert(parent) {
                return Err(GraphError::DuplicateLink { parent, child });
            }
            graph.nodes.get_mut(&parent).unwrap().children.push(child);
        }
        graph.validate()?;
        Ok(graph)
    }

    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }

    pub fn contains(&self, id: ItemId) -> bool {
        self.nodes.contains_key(&id)
    }

    pub fn item_ids(&self) -> impl ExactSizeIterator<Item = ItemId> + '_ {
        self.nodes.keys().copied()
    }

    /// Unplaced items appear as roots; unlinking never deletes an item.
    pub fn roots(&self) -> impl Iterator<Item = ItemId> + '_ {
        self.nodes
            .iter()
            .filter_map(|(&id, node)| node.parents.is_empty().then_some(id))
    }

    pub fn kind(&self, id: ItemId) -> Result<ItemKind, GraphError> {
        Ok(self.node(id)?.kind)
    }

    pub fn children(&self, id: ItemId) -> Result<&[ItemId], GraphError> {
        Ok(&self.node(id)?.children)
    }

    pub fn parents(
        &self,
        id: ItemId,
    ) -> Result<impl ExactSizeIterator<Item = ItemId> + '_, GraphError> {
        Ok(self.node(id)?.parents.iter().copied())
    }

    pub fn add_item(&mut self, id: ItemId, kind: ItemKind) -> Result<(), GraphError> {
        if self.contains(id) {
            return Err(GraphError::DuplicateItem(id));
        }
        self.nodes.insert(
            id,
            Node {
                kind,
                children: Vec::new(),
                parents: BTreeSet::new(),
            },
        );
        Ok(())
    }

    /// Convert an item without changing its ID or placements.
    ///
    /// Completion and visibility policy are the responsibility of higher layers.
    pub fn set_kind(&mut self, id: ItemId, kind: ItemKind) -> Result<(), GraphError> {
        self.nodes
            .get_mut(&id)
            .ok_or(GraphError::MissingItem(id))?
            .kind = kind;
        Ok(())
    }

    /// Append a placement to the parent's children, preserving previous order.
    pub fn link(&mut self, parent: ItemId, child: ItemId) -> Result<(), GraphError> {
        let parent_node = self.node(parent)?;
        self.node(child)?;
        if parent_node.children.contains(&child) {
            return Err(GraphError::DuplicateLink { parent, child });
        }
        if parent == child || self.reachable(child, parent) {
            return Err(GraphError::Cycle { parent, child });
        }

        // Both IDs and the new edge were validated before either side changes.
        self.nodes.get_mut(&parent).unwrap().children.push(child);
        self.nodes.get_mut(&child).unwrap().parents.insert(parent);
        Ok(())
    }

    /// Remove one placement while keeping the item, its children, and other parents.
    pub fn unlink(&mut self, parent: ItemId, child: ItemId) -> Result<(), GraphError> {
        let parent_node = self.node(parent)?;
        self.node(child)?;
        let position = parent_node
            .children
            .iter()
            .position(|&id| id == child)
            .ok_or(GraphError::MissingLink { parent, child })?;

        self.nodes
            .get_mut(&parent)
            .unwrap()
            .children
            .remove(position);
        self.nodes.get_mut(&child).unwrap().parents.remove(&parent);
        Ok(())
    }

    /// Distinct descendants in depth-first child order, excluding `id` itself.
    /// A shared descendant appears once, at its first encounter.
    pub fn descendants(&self, id: ItemId) -> Result<Vec<ItemId>, GraphError> {
        self.node(id)?;
        let mut result = Vec::new();
        let mut visited = BTreeSet::from([id]);
        let mut pending: Vec<_> = self.nodes[&id].children.iter().rev().copied().collect();
        while let Some(current) = pending.pop() {
            if visited.insert(current) {
                result.push(current);
                pending.extend(self.nodes[&current].children.iter().rev().copied());
            }
        }
        Ok(result)
    }

    /// Distinct ancestors in breadth-first order, excluding `id` itself.
    /// At each expansion, parents are visited in ascending ID order.
    pub fn ancestors(&self, id: ItemId) -> Result<Vec<ItemId>, GraphError> {
        self.node(id)?;
        let mut result = Vec::new();
        let mut visited = BTreeSet::from([id]);
        let mut pending: VecDeque<_> = self.nodes[&id].parents.iter().copied().collect();
        while let Some(current) = pending.pop_front() {
            if visited.insert(current) {
                result.push(current);
                pending.extend(self.nodes[&current].parents.iter().copied());
            }
        }
        Ok(result)
    }

    /// Check link symmetry, existing endpoints, unique children, and acyclicity.
    /// The acyclicity check uses iterative topological traversal.
    pub fn validate(&self) -> Result<(), GraphError> {
        for (&id, node) in &self.nodes {
            let mut seen_children = BTreeSet::new();
            for &child in &node.children {
                let child_node = self.node(child)?;
                if !seen_children.insert(child) {
                    return Err(GraphError::InvariantViolation {
                        item: id,
                        reason: "duplicate child placement",
                    });
                }
                if !child_node.parents.contains(&id) {
                    return Err(GraphError::InvariantViolation {
                        item: id,
                        reason: "child is missing the reverse parent reference",
                    });
                }
            }
            for &parent in &node.parents {
                if !self.node(parent)?.children.contains(&id) {
                    return Err(GraphError::InvariantViolation {
                        item: id,
                        reason: "parent is missing the reverse child reference",
                    });
                }
            }
        }

        self.topological_order()?;
        Ok(())
    }

    /// Parents precede their children, without using the call stack.
    pub fn topological_order(&self) -> Result<Vec<ItemId>, GraphError> {
        let mut remaining: BTreeMap<_, _> = self
            .nodes
            .iter()
            .map(|(&id, node)| (id, node.parents.len()))
            .collect();
        let mut pending: VecDeque<_> = self.roots().collect();
        let mut order = Vec::with_capacity(self.len());
        while let Some(current) = pending.pop_front() {
            order.push(current);
            for &child in &self.nodes[&current].children {
                let count = remaining.get_mut(&child).unwrap();
                *count -= 1;
                if *count == 0 {
                    pending.push_back(child);
                }
            }
        }
        if order.len() != self.len() {
            let (&item, _) = remaining.iter().find(|(_, &count)| count > 0).unwrap();
            return Err(GraphError::InvariantViolation {
                item,
                reason: "cycle detected",
            });
        }
        Ok(order)
    }

    fn node(&self, id: ItemId) -> Result<&Node, GraphError> {
        self.nodes.get(&id).ok_or(GraphError::MissingItem(id))
    }

    fn reachable(&self, start: ItemId, target: ItemId) -> bool {
        let mut visited = BTreeSet::new();
        let mut pending = vec![start];
        while let Some(current) = pending.pop() {
            if current == target {
                return true;
            }
            if visited.insert(current) {
                pending.extend(self.nodes[&current].children.iter().copied());
            }
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(value: i64) -> ItemId {
        ItemId::new(value).unwrap()
    }

    fn graph_with_items(count: i64) -> Graph {
        let mut graph = Graph::new();
        for value in 1..=count {
            let kind = if value % 2 == 0 {
                ItemKind::Folder
            } else {
                ItemKind::Task
            };
            graph.add_item(id(value), kind).unwrap();
        }
        graph
    }

    #[test]
    fn ids_must_be_positive_and_can_use_sqlite_integer_range() {
        for invalid in [i64::MIN, -1, 0] {
            assert_eq!(
                ItemId::new(invalid),
                Err(GraphError::InvalidItemId(invalid))
            );
        }
        assert_eq!(id(i64::MAX).get(), i64::MAX);
    }

    #[test]
    fn shared_items_have_the_same_children_and_are_visited_once() {
        let mut graph = graph_with_items(5);
        for (parent, child) in [(1, 2), (1, 3), (2, 4), (3, 4), (4, 5)] {
            graph.link(id(parent), id(child)).unwrap();
        }
        assert_eq!(graph.children(id(2)).unwrap(), [id(4)]);
        assert_eq!(graph.children(id(3)).unwrap(), [id(4)]);
        assert_eq!(graph.children(id(4)).unwrap(), [id(5)]);
        assert_eq!(
            graph.parents(id(4)).unwrap().collect::<Vec<_>>(),
            [id(2), id(3)]
        );
        assert_eq!(
            graph.descendants(id(1)).unwrap(),
            [id(2), id(4), id(5), id(3)]
        );
        assert_eq!(
            graph.ancestors(id(5)).unwrap(),
            [id(4), id(2), id(3), id(1)]
        );
        assert_eq!(graph.validate(), Ok(()));
    }

    #[test]
    fn direct_and_indirect_cycles_are_rejected_without_mutation() {
        let mut graph = graph_with_items(4);
        for (parent, child) in [(1, 2), (2, 3), (3, 4)] {
            graph.link(id(parent), id(child)).unwrap();
        }
        let before = graph.clone();
        for (parent, child) in [(4, 1), (3, 2), (2, 2)] {
            assert_eq!(
                graph.link(id(parent), id(child)),
                Err(GraphError::Cycle {
                    parent: id(parent),
                    child: id(child)
                })
            );
            assert_eq!(graph, before);
        }
        assert_eq!(graph.validate(), Ok(()));
    }

    #[test]
    fn removing_a_placement_preserves_item_children_and_other_placements() {
        let mut graph = graph_with_items(5);
        for (parent, child) in [(1, 3), (1, 4), (1, 5), (2, 4), (4, 5)] {
            graph.link(id(parent), id(child)).unwrap();
        }
        graph.unlink(id(1), id(4)).unwrap();
        assert_eq!(graph.children(id(1)).unwrap(), [id(3), id(5)]);
        assert_eq!(graph.children(id(2)).unwrap(), [id(4)]);
        assert_eq!(graph.children(id(4)).unwrap(), [id(5)]);
        assert_eq!(graph.parents(id(4)).unwrap().collect::<Vec<_>>(), [id(2)]);
        graph.unlink(id(2), id(4)).unwrap();
        assert!(graph.contains(id(4)));
        assert_eq!(graph.len(), 5);
        assert_eq!(graph.roots().collect::<Vec<_>>(), [id(1), id(2), id(4)]);
        assert_eq!(graph.validate(), Ok(()));
    }

    #[test]
    fn missing_items_and_duplicate_operations_are_errors_without_mutation() {
        let mut graph = graph_with_items(2);
        graph.link(id(1), id(2)).unwrap();
        let before = graph.clone();
        assert_eq!(
            graph.add_item(id(1), ItemKind::Folder),
            Err(GraphError::DuplicateItem(id(1)))
        );
        assert_eq!(
            graph.link(id(1), id(2)),
            Err(GraphError::DuplicateLink {
                parent: id(1),
                child: id(2)
            })
        );
        assert_eq!(
            graph.link(id(1), id(3)),
            Err(GraphError::MissingItem(id(3)))
        );
        assert_eq!(
            graph.link(id(3), id(1)),
            Err(GraphError::MissingItem(id(3)))
        );
        assert_eq!(
            graph.unlink(id(2), id(1)),
            Err(GraphError::MissingLink {
                parent: id(2),
                child: id(1)
            })
        );
        assert_eq!(
            graph.unlink(id(1), id(3)),
            Err(GraphError::MissingItem(id(3)))
        );
        assert_eq!(
            graph.set_kind(id(3), ItemKind::Folder),
            Err(GraphError::MissingItem(id(3)))
        );
        assert_eq!(
            graph.descendants(id(3)),
            Err(GraphError::MissingItem(id(3)))
        );
        assert_eq!(graph.ancestors(id(3)), Err(GraphError::MissingItem(id(3))));
        assert_eq!(graph, before);
    }

    #[test]
    fn conversion_preserves_identity_and_relationships() {
        let mut graph = graph_with_items(3);
        graph.link(id(1), id(2)).unwrap();
        graph.link(id(2), id(3)).unwrap();
        graph.set_kind(id(2), ItemKind::Task).unwrap();
        assert_eq!(graph.kind(id(2)), Ok(ItemKind::Task));
        assert_eq!(graph.children(id(2)).unwrap(), [id(3)]);
        assert_eq!(graph.parents(id(2)).unwrap().collect::<Vec<_>>(), [id(1)]);
        assert_eq!(graph.item_ids().collect::<Vec<_>>(), [id(1), id(2), id(3)]);
        assert_eq!(graph.validate(), Ok(()));
    }

    #[test]
    fn very_deep_hierarchies_traverse_and_validate_without_recursion() {
        const DEPTH: i64 = 20_000;
        let mut graph = graph_with_items(DEPTH);
        for parent in 1..DEPTH {
            graph.link(id(parent), id(parent + 1)).unwrap();
        }
        let descendants = graph.descendants(id(1)).unwrap();
        let ancestors = graph.ancestors(id(DEPTH)).unwrap();
        assert_eq!(descendants.len(), (DEPTH - 1) as usize);
        assert_eq!(descendants.last(), Some(&id(DEPTH)));
        assert_eq!(ancestors.len(), (DEPTH - 1) as usize);
        assert_eq!(ancestors.last(), Some(&id(1)));
        assert_eq!(graph.validate(), Ok(()));
        assert_eq!(
            graph.link(id(DEPTH), id(1)),
            Err(GraphError::Cycle {
                parent: id(DEPTH),
                child: id(1)
            })
        );
        assert_eq!(graph.validate(), Ok(()));
    }

    #[test]
    fn graph_invariants_survive_many_shared_placements_and_removals() {
        let mut graph = graph_with_items(40);
        for parent in 1..=40 {
            for child in parent + 1..=40 {
                if (parent + child) % 5 == 0 {
                    graph.link(id(parent), id(child)).unwrap();
                }
            }
        }
        assert_eq!(graph.validate(), Ok(()));
        for parent in (1..=40).rev() {
            for child in graph.children(id(parent)).unwrap().to_vec() {
                graph.unlink(id(parent), child).unwrap();
                assert_eq!(graph.validate(), Ok(()));
            }
        }
        assert_eq!(graph.roots().count(), 40);
    }

    #[test]
    fn validation_detects_inconsistent_backlinks_and_cycles() {
        let mut graph = graph_with_items(2);
        graph.link(id(1), id(2)).unwrap();
        graph.nodes.get_mut(&id(2)).unwrap().parents.clear();
        assert!(matches!(
            graph.validate(),
            Err(GraphError::InvariantViolation { .. })
        ));
        graph.nodes.get_mut(&id(2)).unwrap().parents.insert(id(1));
        graph.nodes.get_mut(&id(2)).unwrap().children.push(id(1));
        graph.nodes.get_mut(&id(1)).unwrap().parents.insert(id(2));
        assert!(matches!(
            graph.validate(),
            Err(GraphError::InvariantViolation {
                reason: "cycle detected",
                ..
            })
        ));
    }
}
