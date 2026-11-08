//! Top-edge pointer trigger for the Windows Workbench.

use display_info::DisplayInfo;
use eframe::egui;
use mouse_position::mouse_position::Mouse;
use serde::{Deserialize, Serialize};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    SW_HIDE, SW_SHOW, SetForegroundWindow, ShowWindow,
};

/// Pointer distance from a display top edge that counts as the trigger zone.
pub(crate) const TOP_EDGE_PIXELS: i32 = 2;
/// Time the pointer must remain in the trigger zone.
pub(crate) const TOP_EDGE_DWELL: Duration = Duration::from_millis(180);
/// Delay after one trigger before another trigger is possible.
pub(crate) const TOP_EDGE_COOLDOWN: Duration = Duration::from_millis(700);
/// Maximum interval between global pointer samples.
pub(crate) const TOP_EDGE_POLL_INTERVAL: Duration = Duration::from_millis(50);

/// Persistent Windows-only host preferences.
#[derive(Debug, Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", default)]
pub(crate) struct WindowsUiSettings {
    /// Enables the top-edge Workbench trigger.
    pub(crate) top_edge_trigger_enabled: bool,
}

/// Debounces the top-edge pointer trigger.
#[derive(Debug, Clone)]
pub(crate) struct TopEdgeTrigger {
    enabled: bool,
    armed: bool,
    inside_since: Option<Instant>,
    cooldown_until: Option<Instant>,
}

/// Polls the top-edge trigger without depending on hidden-window repaint events.
pub(crate) struct TopEdgeMonitor {
    enabled: Arc<AtomicBool>,
    window_visible: Arc<AtomicBool>,
    triggered: Arc<AtomicBool>,
    stop: Arc<AtomicBool>,
    worker: Option<JoinHandle<()>>,
    window_handle: Option<isize>,
    startup_error: Option<String>,
}

impl TopEdgeMonitor {
    /// Starts the pointer monitor with the saved preference and current window state.
    pub(crate) fn new(
        enabled: bool,
        window_visible: bool,
        context: egui::Context,
        window_handle: Option<isize>,
    ) -> Self {
        let enabled = Arc::new(AtomicBool::new(enabled));
        let window_visible = Arc::new(AtomicBool::new(window_visible));
        let triggered = Arc::new(AtomicBool::new(false));
        let stop = Arc::new(AtomicBool::new(false));
        let worker_enabled = Arc::clone(&enabled);
        let worker_visible = Arc::clone(&window_visible);
        let worker_triggered = Arc::clone(&triggered);
        let worker_stop = Arc::clone(&stop);
        let worker = thread::Builder::new()
            .name("covio-top-edge".to_owned())
            .spawn(move || {
                let mut trigger = TopEdgeTrigger::new(worker_enabled.load(Ordering::Acquire));
                while !worker_stop.load(Ordering::Acquire) {
                    let enabled = worker_enabled.load(Ordering::Acquire);
                    if trigger.is_enabled() != enabled {
                        trigger.set_enabled(enabled);
                    }
                    let visible = worker_visible.load(Ordering::Acquire);
                    let at_top = enabled && cursor_at_top_edge();
                    if trigger.update(Instant::now(), visible, at_top) {
                        worker_triggered.store(true, Ordering::Release);
                        if let Some(window_handle) = window_handle {
                            show_native_window(window_handle);
                        }
                        context.request_repaint();
                    }
                    thread::sleep(TOP_EDGE_POLL_INTERVAL);
                }
            });
        let startup_error = window_handle
            .is_none()
            .then(|| "Windows window handle unavailable".to_owned());
        let (worker, startup_error) = match worker {
            Ok(worker) => (Some(worker), startup_error),
            Err(error) => (None, Some(error.to_string())),
        };
        Self {
            enabled,
            window_visible,
            triggered,
            stop,
            worker,
            window_handle,
            startup_error,
        }
    }

    /// Returns whether the trigger is enabled.
    #[must_use]
    pub(crate) fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Acquire)
    }

    /// Enables or disables the background trigger.
    pub(crate) fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Release);
    }

    /// Updates the window state used by the trigger.
    pub(crate) fn set_window_visible(&self, visible: bool) {
        self.window_visible.store(visible, Ordering::Release);
    }

    /// Hides the native window without waiting for an egui pass.
    pub(crate) fn hide_window(&self) {
        if let Some(window_handle) = self.window_handle {
            hide_native_window(window_handle);
        }
    }

    /// Consumes one completed trigger event.
    pub(crate) fn take_triggered(&self) -> bool {
        self.triggered.swap(false, Ordering::AcqRel)
    }

    /// Returns the worker startup error, when one occurred.
    #[must_use]
    pub(crate) fn startup_error(&self) -> Option<&str> {
        self.startup_error.as_deref()
    }
}

#[allow(unsafe_code)]
fn show_native_window(window_handle: isize) {
    // SAFETY: The handle belongs to this process and stays valid until the monitor stops.
    unsafe {
        let _ = ShowWindow(window_handle as _, SW_SHOW);
        let _ = SetForegroundWindow(window_handle as _);
    }
}
/// Hides the host window without waiting for an egui repaint.
#[allow(unsafe_code)]
fn hide_native_window(window_handle: isize) {
    // SAFETY: The handle belongs to this process and is used only while the app is running.
    unsafe {
        let _ = ShowWindow(window_handle as _, SW_HIDE);
    }
}

impl Drop for TopEdgeMonitor {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

impl TopEdgeTrigger {
    /// Creates a trigger with the saved preference.
    #[must_use]
    pub(crate) fn new(enabled: bool) -> Self {
        Self {
            enabled,
            armed: true,
            inside_since: None,
            cooldown_until: None,
        }
    }

    /// Returns whether the trigger is enabled.
    #[must_use]
    pub(crate) fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Enables or disables the trigger and clears transient state.
    pub(crate) fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
        self.armed = true;
        self.inside_since = None;
        self.cooldown_until = None;
    }

    fn update(&mut self, now: Instant, window_visible: bool, at_top: bool) -> bool {
        if !self.enabled {
            self.inside_since = None;
            return false;
        }
        if window_visible {
            self.inside_since = None;
            if !at_top {
                self.armed = true;
            }
            return false;
        }
        if !at_top {
            self.inside_since = None;
            self.armed = true;
            return false;
        }
        if !self.armed
            || self
                .cooldown_until
                .is_some_and(|cooldown_until| now < cooldown_until)
        {
            return false;
        }
        let Some(inside_since) = self.inside_since else {
            self.inside_since = Some(now);
            return false;
        };
        if now.saturating_duration_since(inside_since) < TOP_EDGE_DWELL {
            return false;
        }
        self.inside_since = None;
        self.armed = false;
        self.cooldown_until = Some(now + TOP_EDGE_COOLDOWN);
        true
    }
}

fn cursor_at_top_edge() -> bool {
    let Mouse::Position { x, y } = Mouse::get_mouse_position() else {
        return false;
    };
    DisplayInfo::from_point(x, y).is_ok_and(|display| {
        point_on_display_top(x, y, display.x, display.y, display.width, display.height)
    })
}

fn point_on_display_top(x: i32, y: i32, left: i32, top: i32, width: u32, height: u32) -> bool {
    let right = left.saturating_add(width.min(i32::MAX as u32) as i32);
    let bottom = top.saturating_add(height.min(i32::MAX as u32) as i32);
    let edge_bottom = top.saturating_add(TOP_EDGE_PIXELS).min(bottom);
    x >= left && x < right && y >= top && y < edge_bottom
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ui_settings_round_trip_with_the_saved_key() {
        let settings = WindowsUiSettings {
            top_edge_trigger_enabled: true,
        };
        let json = serde_json::to_string(&settings).expect("settings JSON");
        assert!(json.contains("topEdgeTriggerEnabled"));
        let decoded: WindowsUiSettings = serde_json::from_str(&json).expect("settings decode");
        assert_eq!(decoded, settings);
        assert!(!WindowsUiSettings::default().top_edge_trigger_enabled);
    }

    #[test]
    fn top_edge_uses_two_pixels_and_supports_offset_displays() {
        assert!(point_on_display_top(100, 0, 0, 0, 2560, 1440));
        assert!(point_on_display_top(100, 1, 0, 0, 2560, 1440));
        assert!(!point_on_display_top(100, 2, 0, 0, 2560, 1440));
        assert!(point_on_display_top(-2400, -48, -2560, -48, 2560, 1440));
        assert!(!point_on_display_top(-2400, -46, -2560, -48, 2560, 1440));
    }

    #[test]
    fn dwell_and_cooldown_gate_the_trigger() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, false, true));
        assert!(!trigger.update(start + Duration::from_millis(179), false, true));
        assert!(trigger.update(start + TOP_EDGE_DWELL, false, true));
        assert!(!trigger.update(start + TOP_EDGE_DWELL, false, true));
    }

    #[test]
    fn cooldown_blocks_an_early_reentry() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, false, true));
        assert!(trigger.update(start + TOP_EDGE_DWELL, false, true));
        assert!(!trigger.update(start + TOP_EDGE_DWELL, false, false));
        let early = start + TOP_EDGE_DWELL + TOP_EDGE_COOLDOWN - Duration::from_millis(1);
        assert!(!trigger.update(early, false, true));
        assert!(!trigger.update(early + TOP_EDGE_DWELL, false, true));
    }

    #[test]
    fn pointer_must_leave_and_return_before_rearming() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, false, true));
        assert!(trigger.update(start + TOP_EDGE_DWELL, false, true));
        let after_cooldown = start + TOP_EDGE_DWELL + TOP_EDGE_COOLDOWN;
        assert!(!trigger.update(after_cooldown, false, true));
        assert!(!trigger.update(after_cooldown, false, false));
        assert!(!trigger.update(after_cooldown, false, true));
        assert!(trigger.update(after_cooldown + TOP_EDGE_DWELL, false, true));
    }

    #[test]
    fn disabled_trigger_never_fires() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(false);
        assert!(!trigger.update(start, false, true));
        assert!(!trigger.update(start + TOP_EDGE_DWELL, false, true));
    }

    #[test]
    fn visible_window_never_triggers() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, true, true));
        assert!(!trigger.update(start + TOP_EDGE_DWELL, true, true));
    }
}
