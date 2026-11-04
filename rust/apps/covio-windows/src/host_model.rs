//! Platform-neutral state machine for the Windows host shell.

use crate::{CoreResponse, HostSnapshot};
use serde::{Deserialize, Serialize};

/// Main content selected in the host window.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HostView {
    /// Dashboard and core state counts.
    Home,
    /// Screenshot shelf.
    Shelf,
    /// Clipboard history.
    Clipboard,
    /// Workspace entries.
    Workspace,
    /// Host and core settings.
    Settings,
}

/// Theme choice for the egui host.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ThemePreference {
    /// Follow the Windows application theme.
    System,
    /// Force the light theme.
    Light,
    /// Force the dark theme.
    Dark,
}

/// User-visible status of the core request.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HostStatus {
    /// No request is running.
    Idle,
    /// A core request is running.
    Loading,
    /// The latest request succeeded.
    Ready,
    /// The latest request failed with a user-safe message.
    Error(String),
}

/// Result of the operating-system close request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CloseDisposition {
    /// Hide the window and keep the tray process alive.
    Hide,
    /// Exit the complete host process.
    Exit,
}

/// State machine shared by the egui shell and tests.
#[derive(Debug, Clone)]
pub struct HostModel {
    visible: bool,
    allow_exit: bool,
    view: HostView,
    theme: ThemePreference,
    reduced_motion: bool,
    pending_request: Option<u64>,
    snapshot: Option<HostSnapshot>,
    status: HostStatus,
}

impl HostModel {
    /// Creates a visible host in the Home view.
    #[must_use]
    pub fn new(theme: ThemePreference, reduced_motion: bool) -> Self {
        Self {
            visible: true,
            allow_exit: false,
            view: HostView::Home,
            theme,
            reduced_motion,
            pending_request: None,
            snapshot: None,
            status: HostStatus::Idle,
        }
    }

    /// Returns whether the main window should be visible.
    #[must_use]
    pub fn is_visible(&self) -> bool {
        self.visible
    }

    /// Selects the Home view and shows the window.
    pub fn show_home(&mut self) {
        self.view = HostView::Home;
        self.visible = true;
        self.allow_exit = false;
    }

    /// Selects the Settings view and shows the window.
    pub fn show_settings(&mut self) {
        self.view = HostView::Settings;
        self.visible = true;
        self.allow_exit = false;
    }

    /// Hides the window without stopping the tray process.
    pub fn hide(&mut self) {
        self.visible = false;
    }

    /// Toggles the main window from the tray icon.
    pub fn toggle_from_tray(&mut self) {
        if self.visible {
            self.hide();
        } else {
            self.visible = true;
        }
    }

    /// Handles a close request from the window manager.
    pub fn close_disposition(&mut self) -> CloseDisposition {
        if self.allow_exit {
            CloseDisposition::Exit
        } else {
            self.visible = false;
            CloseDisposition::Hide
        }
    }

    /// Allows the next close request to exit the process.
    pub fn begin_exit(&mut self) {
        self.allow_exit = true;
    }

    /// Returns the selected view.
    #[must_use]
    pub fn view(&self) -> HostView {
        self.view
    }

    /// Selects a view without changing window visibility.
    pub fn select_view(&mut self, view: HostView) {
        self.view = view;
    }

    /// Returns the theme choice.
    #[must_use]
    pub fn theme(&self) -> ThemePreference {
        self.theme
    }

    /// Changes the theme choice.
    pub fn set_theme(&mut self, theme: ThemePreference) {
        self.theme = theme;
    }

    /// Returns whether motion should be reduced.
    #[must_use]
    pub fn reduced_motion(&self) -> bool {
        self.reduced_motion
    }

    /// Changes the reduced-motion preference.
    pub fn set_reduced_motion(&mut self, reduced_motion: bool) {
        self.reduced_motion = reduced_motion;
    }

    /// Marks a request as pending.
    pub fn begin_request(&mut self, request_id: u64) -> bool {
        if self.pending_request.is_some() {
            return false;
        }
        self.pending_request = Some(request_id);
        self.status = HostStatus::Loading;
        true
    }

    /// Clears a canceled request.
    pub fn cancel_request(&mut self, request_id: u64) -> bool {
        if self.pending_request == Some(request_id) {
            self.pending_request = None;
            self.status = HostStatus::Idle;
            true
        } else {
            false
        }
    }

    /// Applies one response from the core worker.
    pub fn apply_response(&mut self, response: CoreResponse) -> bool {
        if self.pending_request != Some(response.request_id) {
            return false;
        }
        self.pending_request = None;
        if !response.ok {
            self.status = HostStatus::Error(
                response
                    .error
                    .map_or_else(|| "Core request failed".to_owned(), |error| error.message),
            );
            return true;
        }
        if response.command == "host.snapshot" {
            match HostSnapshot::from_value(&response.result) {
                Ok(snapshot) => self.snapshot = Some(snapshot),
                Err(error) => {
                    self.status = HostStatus::Error(error);
                    return true;
                }
            }
        }
        self.status = HostStatus::Ready;
        true
    }

    /// Returns the latest snapshot.
    #[must_use]
    pub fn snapshot(&self) -> Option<&HostSnapshot> {
        self.snapshot.as_ref()
    }

    /// Returns the latest request status.
    #[must_use]
    pub fn status(&self) -> &HostStatus {
        &self.status
    }

    /// Returns the pending request id.
    #[must_use]
    pub fn pending_request(&self) -> Option<u64> {
        self.pending_request
    }

    /// Records a local host error without a core response.
    pub fn set_error(&mut self, message: impl Into<String>) {
        self.pending_request = None;
        self.status = HostStatus::Error(message.into());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{HostCoreError, HostSnapshot};
    use serde_json::json;

    fn snapshot_response(request_id: u64) -> CoreResponse {
        CoreResponse {
            request_id,
            command: "host.snapshot".to_owned(),
            ok: true,
            result: serde_json::to_value(HostSnapshot {
                config: json!({"launchAtLogin": false}),
                shelf_item_count: 1,
                clipboard_item_count: 2,
                workspace_entry_count: 3,
                loaded_at_epoch_seconds: 4,
                ..HostSnapshot::default()
            })
            .expect("snapshot JSON"),
            error: None,
        }
    }

    #[test]
    fn close_hides_until_exit_is_requested() {
        let mut model = HostModel::new(ThemePreference::System, false);
        assert_eq!(model.close_disposition(), CloseDisposition::Hide);
        assert!(!model.is_visible());
        model.begin_exit();
        assert_eq!(model.close_disposition(), CloseDisposition::Exit);
    }

    #[test]
    fn tray_toggle_and_settings_control_window_visibility() {
        let mut model = HostModel::new(ThemePreference::Dark, true);
        model.toggle_from_tray();
        assert!(!model.is_visible());
        model.show_settings();
        assert!(model.is_visible());
        assert_eq!(model.view(), HostView::Settings);
        assert_eq!(model.theme(), ThemePreference::Dark);
        assert!(model.reduced_motion());
    }

    #[test]
    fn snapshot_response_updates_host_state() {
        let mut model = HostModel::new(ThemePreference::Light, false);
        assert!(model.begin_request(7));
        assert!(model.apply_response(snapshot_response(7)));
        assert_eq!(model.status(), &HostStatus::Ready);
        let snapshot = model.snapshot().expect("snapshot");
        assert_eq!(snapshot.clipboard_item_count, 2);
        assert_eq!(snapshot.workspace_entry_count, 3);
    }

    #[test]
    fn failed_response_is_visible_and_ignores_unknown_ids() {
        let mut model = HostModel::new(ThemePreference::System, false);
        assert!(model.begin_request(9));
        assert!(!model.apply_response(CoreResponse {
            request_id: 8,
            command: "config.load".to_owned(),
            ok: true,
            result: json!({}),
            error: None,
        }));
        assert!(model.apply_response(CoreResponse {
            request_id: 9,
            command: "config.load".to_owned(),
            ok: false,
            result: json!({}),
            error: Some(HostCoreError {
                code: "config_load_failed".to_owned(),
                message: "cannot read config".to_owned(),
            }),
        }));
        assert_eq!(
            model.status(),
            &HostStatus::Error("cannot read config".to_owned())
        );
    }
}
