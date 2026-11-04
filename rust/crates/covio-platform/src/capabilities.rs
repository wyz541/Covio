//! Stable capability inventory shared by platform adapters and bridge hosts.

use crate::PlatformError;

/// Number of capability kinds in [`CapabilityKind`].
pub const CAPABILITY_KIND_COUNT: usize = 11;

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
    /// System clipboard access.
    Clipboard = 7,
    /// Screenshot source discovery.
    Screenshot = 8,
    /// Current-user startup registration.
    Startup = 9,
    /// Native file picker access.
    FilePicker = 10,
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
            7 => Some(Self::Clipboard),
            8 => Some(Self::Screenshot),
            9 => Some(Self::Startup),
            10 => Some(Self::FilePicker),
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

    /// Requires the capability to be available.
    pub fn require(self) -> Result<(), PlatformError> {
        if self.available {
            Ok(())
        } else {
            Err(PlatformError::unavailable(
                "platform capability is unavailable",
            ))
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
                CapabilityStatus::unavailable(CapabilityKind::Clipboard),
                CapabilityStatus::unavailable(CapabilityKind::Screenshot),
                CapabilityStatus::unavailable(CapabilityKind::Startup),
                CapabilityStatus::unavailable(CapabilityKind::FilePicker),
            ],
        }
    }
}

/// Capability inventory for the native Windows adapter composition.
///
/// Socket and power remain unavailable. The Windows product does not claim a
/// macOS helper, lid, or sleep capability through this adapter set.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WindowsCapabilitySet {
    statuses: [CapabilityStatus; CAPABILITY_KIND_COUNT],
}

impl Default for WindowsCapabilitySet {
    fn default() -> Self {
        Self {
            statuses: [
                CapabilityStatus::available(CapabilityKind::Filesystem),
                CapabilityStatus::available(CapabilityKind::Process),
                CapabilityStatus::unavailable(CapabilityKind::Socket),
                CapabilityStatus::available(CapabilityKind::Notification),
                CapabilityStatus::unavailable(CapabilityKind::Power),
                CapabilityStatus::available(CapabilityKind::Update),
                CapabilityStatus::available(CapabilityKind::SecureStorage),
                CapabilityStatus::available(CapabilityKind::Clipboard),
                CapabilityStatus::available(CapabilityKind::Screenshot),
                CapabilityStatus::available(CapabilityKind::Startup),
                CapabilityStatus::available(CapabilityKind::FilePicker),
            ],
        }
    }
}

impl WindowsCapabilitySet {
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
            CapabilityKind::Clipboard,
            CapabilityKind::Screenshot,
            CapabilityKind::Startup,
            CapabilityKind::FilePicker,
        ] {
            assert!(!capabilities.status(kind).available, "{kind:?}");
        }
    }

    #[test]
    fn windows_inventory_exposes_native_adapters_and_typed_unavailability() {
        let capabilities = WindowsCapabilitySet::default();
        for kind in [
            CapabilityKind::Filesystem,
            CapabilityKind::Process,
            CapabilityKind::Notification,
            CapabilityKind::Update,
            CapabilityKind::SecureStorage,
            CapabilityKind::Clipboard,
            CapabilityKind::Screenshot,
            CapabilityKind::Startup,
            CapabilityKind::FilePicker,
        ] {
            capabilities
                .status(kind)
                .require()
                .unwrap_or_else(|_| panic!("{kind:?} should be available"));
        }
        for kind in [CapabilityKind::Socket, CapabilityKind::Power] {
            let error = capabilities
                .status(kind)
                .require()
                .expect_err("capability should be unavailable");
            assert_eq!(error.code(), crate::PlatformErrorCode::Unavailable);
        }
    }
}
