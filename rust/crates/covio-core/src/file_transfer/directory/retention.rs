//! Retention policy for transfer staging and metadata.

use super::super::{TransferError, TransferState};
use serde::{Deserialize, Serialize};

/// Default retention for staging data of paused or unfinished tasks.
pub const PAUSED_STAGING_RETENTION_MS: i64 = 7 * 24 * 60 * 60 * 1_000;
/// Default retention for staging data of cancelled tasks.
pub const CANCELLED_STAGING_RETENTION_MS: i64 = 24 * 60 * 60 * 1_000;
/// Default retention for staging data of failed tasks.
pub const FAILED_STAGING_RETENTION_MS: i64 = 7 * 24 * 60 * 60 * 1_000;
/// Default retention for completed or terminal task metadata.
pub const TERMINAL_METADATA_RETENTION_MS: i64 = 30 * 24 * 60 * 60 * 1_000;

/// Configurable transfer retention policy.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", default)]
pub struct TransferRetentionPolicy {
    /// Paused, background-deferred, or network-waiting staging lifetime.
    pub paused_staging_ms: i64,
    /// Cancelled staging lifetime.
    pub cancelled_staging_ms: i64,
    /// Failed or rejected staging lifetime.
    pub failed_staging_ms: i64,
    /// Completed or otherwise terminal metadata lifetime.
    pub terminal_metadata_ms: i64,
}

impl Default for TransferRetentionPolicy {
    fn default() -> Self {
        Self {
            paused_staging_ms: PAUSED_STAGING_RETENTION_MS,
            cancelled_staging_ms: CANCELLED_STAGING_RETENTION_MS,
            failed_staging_ms: FAILED_STAGING_RETENTION_MS,
            terminal_metadata_ms: TERMINAL_METADATA_RETENTION_MS,
        }
    }
}

impl TransferRetentionPolicy {
    /// Returns a normalized policy with nonnegative durations.
    #[must_use]
    pub fn normalized(self) -> Self {
        Self {
            paused_staging_ms: self.paused_staging_ms.max(0),
            cancelled_staging_ms: self.cancelled_staging_ms.max(0),
            failed_staging_ms: self.failed_staging_ms.max(0),
            terminal_metadata_ms: self.terminal_metadata_ms.max(0),
        }
    }
}

/// Minimal durable task fields required by retention decisions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct RetentionTask {
    /// Transfer identifier.
    pub transfer_id: String,
    /// Current durable state.
    pub state: TransferState,
    /// Last durable state update time.
    pub updated_at_ms: i64,
}

/// One retention decision. Final destination files are never targeted.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct RetentionDecision {
    /// Task evaluated by this decision.
    pub task: RetentionTask,
    /// Remove the task staging directory and chunk checkpoints.
    pub clean_staging: bool,
    /// Remove terminal task metadata and audit events.
    pub purge_metadata: bool,
}

/// Deterministic retention plan.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct RetentionPlan {
    /// Actions to apply in task order.
    pub decisions: Vec<RetentionDecision>,
}

impl RetentionPlan {
    /// Returns the number of tasks with staging cleanup.
    #[must_use]
    pub fn staging_count(&self) -> usize {
        self.decisions
            .iter()
            .filter(|decision| decision.clean_staging)
            .count()
    }

    /// Returns the number of tasks with metadata purge.
    #[must_use]
    pub fn metadata_count(&self) -> usize {
        self.decisions
            .iter()
            .filter(|decision| decision.purge_metadata)
            .count()
    }
}

/// Plans staging and metadata cleanup without touching final destination files.
#[must_use]
pub fn plan_retention(
    tasks: &[RetentionTask],
    now_ms: i64,
    policy: TransferRetentionPolicy,
) -> RetentionPlan {
    let policy = policy.normalized();
    let decisions = tasks
        .iter()
        .filter_map(|task| {
            let age = now_ms.saturating_sub(task.updated_at_ms.max(0));
            let clean_staging = match task.state {
                TransferState::Paused
                | TransferState::BackgroundDeferred
                | TransferState::WaitingNetwork => age >= policy.paused_staging_ms,
                TransferState::Cancelled => age >= policy.cancelled_staging_ms,
                TransferState::Failed | TransferState::Rejected | TransferState::Expired => {
                    age >= policy.failed_staging_ms
                }
                TransferState::Completed => true,
                TransferState::OfferWaiting
                | TransferState::AwaitingAcceptance
                | TransferState::Transferring
                | TransferState::Verifying
                | TransferState::Committing => false,
            };
            let purge_metadata = is_terminal(task.state) && age >= policy.terminal_metadata_ms;
            (clean_staging || purge_metadata).then(|| RetentionDecision {
                task: task.clone(),
                clean_staging,
                purge_metadata,
            })
        })
        .collect();
    RetentionPlan { decisions }
}

/// Returns whether a state is terminal.
#[must_use]
pub const fn is_terminal(state: TransferState) -> bool {
    matches!(
        state,
        TransferState::Completed
            | TransferState::Rejected
            | TransferState::Expired
            | TransferState::Cancelled
            | TransferState::Failed
    )
}

/// Rejects a retention policy that cannot be applied.
pub fn validate_retention_policy(
    policy: TransferRetentionPolicy,
) -> Result<TransferRetentionPolicy, TransferError> {
    if policy.paused_staging_ms < 0
        || policy.cancelled_staging_ms < 0
        || policy.failed_staging_ms < 0
        || policy.terminal_metadata_ms < 0
    {
        return Err(TransferError::invalid(
            "retention durations must not be negative",
        ));
    }
    Ok(policy)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn task(id: &str, state: TransferState, updated_at_ms: i64) -> RetentionTask {
        RetentionTask {
            transfer_id: id.to_owned(),
            state,
            updated_at_ms,
        }
    }

    #[test]
    fn plan_applies_state_specific_deadlines() {
        let tasks = vec![
            task("paused", TransferState::Paused, 0),
            task("cancelled", TransferState::Cancelled, 0),
            task("failed", TransferState::Failed, 0),
            task("completed", TransferState::Completed, 0),
        ];
        let plan = plan_retention(
            &tasks,
            TERMINAL_METADATA_RETENTION_MS,
            TransferRetentionPolicy::default(),
        );
        assert_eq!(plan.staging_count(), 4);
        assert_eq!(plan.metadata_count(), 3);
        assert!(
            !plan
                .decisions
                .iter()
                .any(|decision| decision.task.transfer_id == "paused" && decision.purge_metadata)
        );
    }

    #[test]
    fn active_tasks_are_not_cleaned() {
        let plan = plan_retention(
            &[task("active", TransferState::Transferring, 0)],
            i64::MAX,
            TransferRetentionPolicy::default(),
        );
        assert!(plan.decisions.is_empty());
    }

    #[test]
    fn negative_durations_are_rejected() {
        let policy = TransferRetentionPolicy {
            cancelled_staging_ms: -1,
            ..TransferRetentionPolicy::default()
        };
        assert!(validate_retention_policy(policy).is_err());
    }
}
