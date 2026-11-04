//! Stable capability inventory shared by platform adapters and bridge hosts.

/// Number of capability kinds in [`CapabilityKind`].
pub const CAPABILITY_KIND_COUNT: usize = 7;

/// One platform capability that the core can require.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum CapabilityKind {
    /// Durable file access.
    Filesystem = 0,
    /// Child-process execution.
    Process = 1,
    /// Local socket access.
    Socket = 2,
    /// User notifications.
    Notification = 3,
    /// Power, lid, and sleep access.
    Power = 4,
    /// Update source access.
    Update = 5,
    /// Secret storage.
    SecureStorage = 6,
}

impl CapabilityKind {
    /// Converts a stable C ABI value.
    #[must_use]
    pub const fn from_wire(value: u32) -> Option<Self> {
        match value {
            0 => Some(Self::Filesystem),
            1 => Some(Self::Process),
            2 => Some(Self::Socket),
            3 => Some(Self::Notification),
            4 => Some(Self::Power),
            5 => Some(Self::Update),
            6 => Some(Self::SecureStorage),
            _ => None,
        }
    }
}

/// Availability of one platform capability.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CapabilityStatus {
    /// Capability identifier.
    pub kind: CapabilityKind,
    /// Whether the adapter can perform the capability.
    pub available: bool,
}

impl CapabilityStatus {
    /// Creates an available status.
    #[must_use]
    pub const fn available(kind: CapabilityKind) -> Self {
        Self {
            kind,
            available: true,
        }
    }

    /// Creates an unavailable status.
    #[must_use]
    pub const fn unavailable(kind: CapabilityKind) -> Self {
        Self {
            kind,
            available: false,
        }
    }
}

/// Capability inventory for the native macOS adapter composition.
///
/// Filesystem and secure storage are native adapters in this crate.
/// Process, socket, notification, power, and update stay unavailable until the
/// macOS product composition wires their concrete OS adapters.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MacCapabilitySet {
    statuses: [CapabilityStatus; CAPABILITY_KIND_COUNT],
}

impl Default for MacCapabilitySet {
    fn default() -> Self {
        Self {
            statuses: [
                CapabilityStatus::available(CapabilityKind::Filesystem),
                CapabilityStatus::unavailable(CapabilityKind::Process),
                CapabilityStatus::unavailable(CapabilityKind::Socket),
                CapabilityStatus::unavailable(CapabilityKind::Notification),
                CapabilityStatus::unavailable(CapabilityKind::Power),
                CapabilityStatus::unavailable(CapabilityKind::Update),
                CapabilityStatus::available(CapabilityKind::SecureStorage),
            ],
        }
    }
}

impl MacCapabilitySet {
    /// Returns one capability status.
    #[must_use]
    pub const fn status(self, kind: CapabilityKind) -> CapabilityStatus {
        self.statuses[kind as usize]
    }

    /// Returns every capability status.
    #[must_use]
    pub const fn statuses(self) -> [CapabilityStatus; CAPABILITY_KIND_COUNT] {
        self.statuses
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_values_round_trip() {
        for value in 0..CAPABILITY_KIND_COUNT as u32 {
            let kind = CapabilityKind::from_wire(value).expect("known kind");
            assert_eq!(kind as u32, value);
        }
        assert_eq!(CapabilityKind::from_wire(99), None);
    }

    #[test]
    fn mac_inventory_does_not_claim_unwired_adapters() {
        let capabilities = MacCapabilitySet::default();
        assert!(capabilities.status(CapabilityKind::Filesystem).available);
        assert!(capabilities.status(CapabilityKind::SecureStorage).available);
        for kind in [
            CapabilityKind::Process,
            CapabilityKind::Socket,
            CapabilityKind::Notification,
            CapabilityKind::Power,
            CapabilityKind::Update,
        ] {
            assert!(!capabilities.status(kind).available, "{kind:?}");
        }
    }
}
