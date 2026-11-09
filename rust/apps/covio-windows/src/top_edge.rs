//! Top-edge pointer trigger for the Windows Workbench.

use crate::visuals::PANEL_RADIUS;
use covio_core::workbench_interaction::{Platform, WORKBENCH_INTERACTION};
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
use windows_sys::Win32::Foundation::RECT;
use windows_sys::Win32::Graphics::Dwm::{
    DWM_BB_BLURREGION, DWM_BB_ENABLE, DWM_BLURBEHIND, DWMNCRP_DISABLED, DWMWA_BORDER_COLOR,
    DWMWA_COLOR_NONE, DWMWA_NCRENDERING_POLICY, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_DONOTROUND,
    DwmEnableBlurBehindWindow, DwmSetWindowAttribute,
};
use windows_sys::Win32::Graphics::Gdi::{
    CreateRectRgn, CreateRoundRectRgn, DeleteObject, SetWindowRgn,
};
use windows_sys::Win32::UI::HiDpi::GetDpiForWindow;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    GWL_EXSTYLE, GWL_STYLE, GetWindowLongPtrW, GetWindowRect, HWND_TOPMOST, SW_HIDE, SW_SHOW,
    SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_SHOWWINDOW, SetForegroundWindow,
    SetWindowLongPtrW, SetWindowPos, ShowWindow, WS_CAPTION, WS_EX_APPWINDOW, WS_EX_TOOLWINDOW,
    WS_EX_TOPMOST, WS_MAXIMIZEBOX, WS_MINIMIZEBOX, WS_SYSMENU, WS_THICKFRAME,
};

/// Maximum interval between global pointer samples.
pub(crate) const TOP_EDGE_POLL_INTERVAL: Duration = Duration::from_millis(50);
/// Maximum interval between native Workbench animation frames.
const WORKBENCH_ANIMATION_FRAME_INTERVAL: Duration = Duration::from_millis(8);

fn trigger_dwell() -> Duration {
    WORKBENCH_INTERACTION.trigger_dwell_duration(Platform::Windows)
}

fn trigger_cooldown() -> Duration {
    WORKBENCH_INTERACTION.trigger_cooldown_duration(Platform::Windows)
}

fn required_windows_override(field: &str) -> f64 {
    WORKBENCH_INTERACTION
        .platform_value(Platform::Windows, field)
        .unwrap_or_else(|| panic!("missing Windows Workbench override: {field}"))
}

fn trigger_half_width_percent() -> i64 {
    required_windows_override("trigger.geometry.centeredHalfWidthPercent").round() as i64
}

fn trigger_edge_thickness_pixels() -> i64 {
    required_windows_override("trigger.geometry.topEdgeThicknessPixels").round() as i64
}

/// Persistent Windows-only host preferences.
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", default)]
pub(crate) struct WindowsUiSettings {
    /// Enables the top-edge Workbench trigger.
    pub(crate) top_edge_trigger_enabled: bool,
}

impl Default for WindowsUiSettings {
    fn default() -> Self {
        Self {
            top_edge_trigger_enabled: true,
        }
    }
}

/// Debounces the top-edge pointer trigger.
#[derive(Debug, Clone)]
pub(crate) struct TopEdgeTrigger {
    enabled: bool,
    armed: bool,
    inside_since: Option<Instant>,
    cooldown_until: Option<Instant>,
}

/// Tracks how long the pointer has stayed outside the visible Workbench.
struct AutoHideTracker {
    delay: Duration,
    outside_since: Option<Instant>,
}

impl AutoHideTracker {
    fn new(delay: Duration) -> Self {
        Self {
            delay,
            outside_since: None,
        }
    }

    fn update(&mut self, now: Instant, inside: bool) -> bool {
        if inside {
            self.outside_since = None;
            return false;
        }
        let outside_since = *self.outside_since.get_or_insert(now);
        now.saturating_duration_since(outside_since) >= self.delay
    }

    fn reset(&mut self) {
        self.outside_since = None;
    }
}

/// Polls the top-edge trigger without depending on hidden-window repaint events.
pub(crate) struct TopEdgeMonitor {
    enabled: Arc<AtomicBool>,
    window_visible: Arc<AtomicBool>,
    auto_hide_enabled: Arc<AtomicBool>,
    reduced_motion: Arc<AtomicBool>,
    triggered: Arc<AtomicBool>,
    hide_requested: Arc<AtomicBool>,
    render_ready: Arc<AtomicBool>,
    overlay_revealed: Arc<AtomicBool>,
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
        reduced_motion: bool,
        context: egui::Context,
        window_handle: Option<isize>,
    ) -> Self {
        let enabled = Arc::new(AtomicBool::new(enabled));
        let window_visible = Arc::new(AtomicBool::new(window_visible));
        let auto_hide_enabled = Arc::new(AtomicBool::new(true));
        let reduced_motion = Arc::new(AtomicBool::new(reduced_motion));
        let triggered = Arc::new(AtomicBool::new(false));
        let hide_requested = Arc::new(AtomicBool::new(false));
        let render_ready = Arc::new(AtomicBool::new(false));
        let overlay_revealed = Arc::new(AtomicBool::new(false));
        let stop = Arc::new(AtomicBool::new(false));
        let worker_enabled = Arc::clone(&enabled);
        let worker_visible = Arc::clone(&window_visible);
        let worker_auto_hide_enabled = Arc::clone(&auto_hide_enabled);
        let worker_reduced_motion = Arc::clone(&reduced_motion);
        let worker_triggered = Arc::clone(&triggered);
        let worker_hide_requested = Arc::clone(&hide_requested);
        let worker_render_ready = Arc::clone(&render_ready);
        let worker_overlay_revealed = Arc::clone(&overlay_revealed);
        let worker_stop = Arc::clone(&stop);
        let worker = thread::Builder::new()
            .name("covio-top-edge".to_owned())
            .spawn(move || {
                let mut trigger = TopEdgeTrigger::new(worker_enabled.load(Ordering::Acquire));
                let mut auto_hide = AutoHideTracker::new(
                    WORKBENCH_INTERACTION.pointer_exit_collapse_duration(Platform::Windows),
                );
                while !worker_stop.load(Ordering::Acquire) {
                    let now = Instant::now();
                    let enabled = worker_enabled.load(Ordering::Acquire);
                    if trigger.is_enabled() != enabled {
                        trigger.set_enabled(enabled);
                    }
                    let visible = worker_visible.load(Ordering::Acquire);
                    let cursor = mouse_point();
                    let at_top = enabled && cursor.is_some_and(|(x, y)| point_at_top_edge(x, y));

                    if trigger.update(now, visible, at_top) {
                        worker_triggered.store(true, Ordering::Release);
                        if let Some(window_handle) = window_handle {
                            worker_overlay_revealed.store(false, Ordering::Release);
                            worker_render_ready.store(false, Ordering::Release);
                            show_native_window_offscreen(window_handle);
                            context.request_repaint();
                            let deadline = now + Duration::from_millis(750);
                            while !worker_render_ready.load(Ordering::Acquire)
                                && Instant::now() < deadline
                            {
                                thread::sleep(Duration::from_millis(10));
                            }
                            reveal_native_window(
                                window_handle,
                                cursor,
                                worker_reduced_motion.load(Ordering::Acquire),
                            );
                            worker_overlay_revealed.store(true, Ordering::Release);
                            worker_render_ready.store(false, Ordering::Release);
                        } else {
                            context.request_repaint();
                        }
                    }

                    let auto_hide_enabled = worker_auto_hide_enabled.load(Ordering::Acquire);
                    let overlay_revealed = worker_overlay_revealed.load(Ordering::Acquire);
                    let pointer_inside = cursor
                        .zip(window_handle)
                        .is_some_and(|((x, y), handle)| window_contains_point(handle, x, y));
                    if visible
                        && overlay_revealed
                        && auto_hide_enabled
                        && auto_hide.update(now, pointer_inside)
                    {
                        worker_overlay_revealed.store(false, Ordering::Release);
                        if let Some(window_handle) = window_handle {
                            conceal_native_window(
                                window_handle,
                                worker_reduced_motion.load(Ordering::Acquire),
                            );
                        }
                        worker_hide_requested.store(true, Ordering::Release);
                        context.request_repaint();
                    } else if !visible || !overlay_revealed || !auto_hide_enabled {
                        auto_hide.reset();
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
            auto_hide_enabled,
            reduced_motion,
            triggered,
            hide_requested,
            render_ready,
            overlay_revealed,
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
        if !visible {
            self.overlay_revealed.store(false, Ordering::Release);
        }
    }

    /// Enables auto-hide for Workbench pages.
    pub(crate) fn set_auto_hide_enabled(&self, enabled: bool) {
        self.auto_hide_enabled.store(enabled, Ordering::Release);
    }

    /// Updates the reduced-motion preference used by native transitions.
    pub(crate) fn set_reduced_motion(&self, reduced_motion: bool) {
        self.reduced_motion.store(reduced_motion, Ordering::Release);
    }

    /// Consumes one completed auto-hide request.
    pub(crate) fn take_hide_requested(&self) -> bool {
        self.hide_requested.swap(false, Ordering::AcqRel)
    }

    /// Marks the current egui frame as rendered for the pending reveal.
    pub(crate) fn mark_window_rendered(&self) {
        self.render_ready.store(true, Ordering::Release);
    }

    /// Hides the native window without waiting for an egui pass.
    pub(crate) fn hide_window(&self) {
        self.overlay_revealed.store(false, Ordering::Release);
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
pub(crate) fn configure_overlay_window(window_handle: isize) {
    // SAFETY: The handle belongs to this process and remains valid while the app runs.
    unsafe {
        let style = GetWindowLongPtrW(window_handle as _, GWL_STYLE) as u32;
        let style =
            style & !(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        let _ = SetWindowLongPtrW(window_handle as _, GWL_STYLE, style as isize);

        let ex_style = GetWindowLongPtrW(window_handle as _, GWL_EXSTYLE) as u32;
        let ex_style = (ex_style & !WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW | WS_EX_TOPMOST;
        let _ = SetWindowLongPtrW(window_handle as _, GWL_EXSTYLE, ex_style as isize);
        let _ = SetWindowPos(
            window_handle as _,
            HWND_TOPMOST,
            0,
            0,
            0,
            0,
            SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
        );

        let corner_preference = DWMWCP_DONOTROUND;
        let _ = DwmSetWindowAttribute(
            window_handle as _,
            DWMWA_WINDOW_CORNER_PREFERENCE as u32,
            (&corner_preference as *const i32).cast(),
            std::mem::size_of::<i32>() as u32,
        );
        let border_color = DWMWA_COLOR_NONE;
        let _ = DwmSetWindowAttribute(
            window_handle as _,
            DWMWA_BORDER_COLOR as u32,
            (&border_color as *const u32).cast(),
            std::mem::size_of::<u32>() as u32,
        );

        let non_client_rendering = DWMNCRP_DISABLED;
        let _ = DwmSetWindowAttribute(
            window_handle as _,
            DWMWA_NCRENDERING_POLICY as u32,
            (&non_client_rendering as *const i32).cast(),
            std::mem::size_of::<i32>() as u32,
        );

        let (width, height) = window_dimensions(window_handle);
        if width > 0 && height > 0 {
            let radius = window_region_radius(GetDpiForWindow(window_handle as _));
            let region = CreateRoundRectRgn(0, 0, width + 1, height + 1, radius * 2, radius * 2);
            if !region.is_null() && SetWindowRgn(window_handle as _, region, 1) == 0 {
                let _ = DeleteObject(region);
            }
        }

        let empty_region = CreateRectRgn(0, 0, -1, -1);
        if !empty_region.is_null() {
            let blur = DWM_BLURBEHIND {
                dwFlags: DWM_BB_ENABLE | DWM_BB_BLURREGION,
                fEnable: 1,
                hRgnBlur: empty_region,
                fTransitionOnMaximized: 0,
            };
            let _ = DwmEnableBlurBehindWindow(window_handle as _, &blur);
            let _ = DeleteObject(empty_region);
        }
    }
}

#[allow(unsafe_code)]
fn reveal_native_window(window_handle: isize, cursor: Option<(i32, i32)>, reduced_motion: bool) {
    let dimensions = window_dimensions(window_handle);
    if let Some(display) = cursor.and_then(display_for_point) {
        let x = centered_display_x(display.x, display.width, dimensions.0);
        let hidden_y = display.y.saturating_sub(dimensions.1);
        animate_native_window_y(
            window_handle,
            x,
            hidden_y,
            display.y,
            dimensions,
            animation_duration(true, reduced_motion),
        );
    }
    // SAFETY: The handle belongs to this process and stays valid until the monitor stops.
    unsafe {
        let _ = ShowWindow(window_handle as _, SW_SHOW);
        let _ = SetForegroundWindow(window_handle as _);
    }
    configure_overlay_window(window_handle);
}

#[allow(unsafe_code)]
fn conceal_native_window(window_handle: isize, reduced_motion: bool) {
    let Some(rect) = window_rect(window_handle) else {
        return;
    };
    let Some(display) = display_for_window(window_handle) else {
        return;
    };
    let width = rect.right.saturating_sub(rect.left);
    let height = rect.bottom.saturating_sub(rect.top);
    animate_native_window_y(
        window_handle,
        rect.left,
        rect.top,
        display.y.saturating_sub(height),
        (width, height),
        animation_duration(false, reduced_motion),
    );
}

fn animate_native_window_y(
    window_handle: isize,
    x: i32,
    start_y: i32,
    end_y: i32,
    (width, height): (i32, i32),
    duration: Duration,
) {
    if duration.is_zero() {
        set_native_window_position(window_handle, x, end_y, width, height);
        return;
    }

    let started = Instant::now();
    loop {
        let elapsed = started.elapsed();
        let progress = (elapsed.as_secs_f64() / duration.as_secs_f64()).clamp(0.0, 1.0);
        let y = animated_y(start_y, end_y, progress);
        set_native_window_position(window_handle, x, y, width, height);
        if progress >= 1.0 {
            break;
        }
        thread::sleep(
            duration
                .saturating_sub(elapsed)
                .min(WORKBENCH_ANIMATION_FRAME_INTERVAL),
        );
    }
}

#[allow(unsafe_code)]
fn set_native_window_position(window_handle: isize, x: i32, y: i32, width: i32, height: i32) {
    // SAFETY: The handle belongs to this process and each coordinate comes from Win32.
    unsafe {
        let _ = SetWindowPos(
            window_handle as _,
            HWND_TOPMOST,
            x,
            y,
            width,
            height,
            SWP_NOACTIVATE,
        );
    }
}

fn animation_duration(expanding: bool, reduced_motion: bool) -> Duration {
    if reduced_motion {
        WORKBENCH_INTERACTION.reduced_motion_duration(Platform::Windows)
    } else if expanding {
        WORKBENCH_INTERACTION.reveal_duration(Platform::Windows)
    } else {
        WORKBENCH_INTERACTION.conceal_duration(Platform::Windows)
    }
}

fn ease_out_cubic(progress: f64) -> f64 {
    let inverse = 1.0 - progress.clamp(0.0, 1.0);
    1.0 - inverse.powi(3)
}

fn animated_y(start_y: i32, end_y: i32, progress: f64) -> i32 {
    let start = f64::from(start_y);
    let distance = f64::from(end_y) - start;
    (start + distance * ease_out_cubic(progress))
        .round()
        .clamp(f64::from(i32::MIN), f64::from(i32::MAX)) as i32
}

#[allow(unsafe_code)]
fn show_native_window_offscreen(window_handle: isize) {
    let (width, height) = window_dimensions(window_handle);
    configure_overlay_window(window_handle);
    // SAFETY: The handle belongs to this process and the off-screen coordinates are valid.
    unsafe {
        let _ = SetWindowPos(
            window_handle as _,
            HWND_TOPMOST,
            -10_000,
            -10_000,
            width,
            height,
            SWP_NOACTIVATE | SWP_SHOWWINDOW,
        );
    }
}

#[allow(unsafe_code)]
fn window_rect(window_handle: isize) -> Option<RECT> {
    let mut rect = std::mem::MaybeUninit::<RECT>::zeroed();
    // SAFETY: GetWindowRect writes a complete RECT for a valid process window.
    let result = unsafe { GetWindowRect(window_handle as _, rect.as_mut_ptr()) };
    if result == 0 {
        return None;
    }
    // SAFETY: A successful call initialized the RECT.
    Some(unsafe { rect.assume_init() })
}

fn window_dimensions(window_handle: isize) -> (i32, i32) {
    window_rect(window_handle).map_or((0, 0), |rect| {
        (
            rect.right.saturating_sub(rect.left),
            rect.bottom.saturating_sub(rect.top),
        )
    })
}

fn window_contains_point(window_handle: isize, x: i32, y: i32) -> bool {
    window_rect(window_handle)
        .is_some_and(|rect| x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom)
}

fn window_region_radius(dpi: u32) -> i32 {
    let dpi = i64::from(dpi.max(96));
    (i64::from(PANEL_RADIUS) * dpi / 96).clamp(1, i64::from(i32::MAX / 2)) as i32
}

fn display_for_point((x, y): (i32, i32)) -> Option<DisplayInfo> {
    DisplayInfo::from_point(x, y).ok()
}

fn display_for_window(window_handle: isize) -> Option<DisplayInfo> {
    let rect = window_rect(window_handle)?;
    let x = rect.left + rect.right.saturating_sub(rect.left) / 2;
    display_for_point((x, rect.top.saturating_add(1)))
}

fn centered_display_x(left: i32, width: u32, window_width: i32) -> i32 {
    let display_width = width.min(i32::MAX as u32) as i32;
    left.saturating_add(display_width.saturating_sub(window_width).max(0) / 2)
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
        if now.saturating_duration_since(inside_since) < trigger_dwell() {
            return false;
        }
        self.inside_since = None;
        self.armed = false;
        self.cooldown_until = Some(now + trigger_cooldown());
        true
    }
}

fn mouse_point() -> Option<(i32, i32)> {
    match Mouse::get_mouse_position() {
        Mouse::Position { x, y } => Some((x, y)),
        Mouse::Error => None,
    }
}

fn point_at_top_edge(x: i32, y: i32) -> bool {
    display_for_point((x, y)).is_some_and(|display| {
        point_on_display_top(x, y, display.x, display.y, display.width, display.height)
    })
}

fn point_on_display_top(x: i32, y: i32, left: i32, top: i32, width: u32, height: u32) -> bool {
    let x = i64::from(x);
    let y = i64::from(y);
    let left = i64::from(left);
    let top = i64::from(top);
    let width = i64::from(width.min(i32::MAX as u32) as i32);
    let height = i64::from(height.min(i32::MAX as u32) as i32);
    let half_width_percent = trigger_half_width_percent();
    let trigger_left = left + width * (50 - half_width_percent) / 100;
    let trigger_right = left + width * (50 + half_width_percent) / 100;
    let trigger_bottom = top + trigger_edge_thickness_pixels().min(height);
    x >= trigger_left && x < trigger_right && y >= top && y < trigger_bottom
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
        assert!(WindowsUiSettings::default().top_edge_trigger_enabled);
    }

    #[test]
    fn top_edge_uses_the_contract_center_and_supports_offset_displays() {
        let half_width = trigger_half_width_percent();
        let thickness = trigger_edge_thickness_pixels();
        let width = 2560_i64;
        let left = 0_i64;
        let center = left + width / 2;
        let trigger_left = left + width * (50 - half_width) / 100;
        let trigger_right = left + width * (50 + half_width) / 100;

        assert!(!point_on_display_top(
            (trigger_left - 1) as i32,
            0,
            0,
            0,
            2560,
            1440
        ));
        assert!(point_on_display_top(
            trigger_left as i32,
            0,
            0,
            0,
            2560,
            1440
        ));
        assert!(point_on_display_top(
            center as i32,
            (thickness - 1) as i32,
            0,
            0,
            2560,
            1440
        ));
        assert!(!point_on_display_top(
            center as i32,
            thickness as i32,
            0,
            0,
            2560,
            1440
        ));
        assert!(point_on_display_top(
            (trigger_right - 1) as i32,
            0,
            0,
            0,
            2560,
            1440
        ));
        assert!(!point_on_display_top(
            trigger_right as i32,
            0,
            0,
            0,
            2560,
            1440
        ));

        let offset_left = -2560_i64;
        let offset_top = -48_i64;
        let offset_trigger_left = offset_left + width * (50 - half_width) / 100;
        let offset_trigger_right = offset_left + width * (50 + half_width) / 100;
        assert!(!point_on_display_top(
            (offset_trigger_left - 1) as i32,
            offset_top as i32,
            offset_left as i32,
            offset_top as i32,
            2560,
            1440,
        ));
        assert!(point_on_display_top(
            offset_trigger_left as i32,
            offset_top as i32,
            offset_left as i32,
            offset_top as i32,
            2560,
            1440,
        ));
        assert!(point_on_display_top(
            -1280,
            (offset_top + thickness - 1) as i32,
            offset_left as i32,
            offset_top as i32,
            2560,
            1440,
        ));
        assert!(!point_on_display_top(
            (offset_trigger_right) as i32,
            offset_top as i32,
            offset_left as i32,
            offset_top as i32,
            2560,
            1440,
        ));
    }

    #[test]
    fn workbench_animation_comes_from_the_interaction_contract() {
        assert_eq!(
            animation_duration(true, false),
            WORKBENCH_INTERACTION.reveal_duration(Platform::Windows)
        );
        assert_eq!(
            animation_duration(false, false),
            WORKBENCH_INTERACTION.conceal_duration(Platform::Windows)
        );
        assert_eq!(
            animation_duration(true, true),
            WORKBENCH_INTERACTION.reduced_motion_duration(Platform::Windows)
        );
        assert_eq!(
            animation_duration(false, true),
            WORKBENCH_INTERACTION.reduced_motion_duration(Platform::Windows)
        );
    }

    #[test]
    fn native_animation_uses_ease_out_progress() {
        assert_eq!(ease_out_cubic(0.0), 0.0);
        assert!((ease_out_cubic(0.5) - 0.875).abs() < f64::EPSILON);
        assert_eq!(ease_out_cubic(1.0), 1.0);
        assert_eq!(animated_y(-880, 0, 0.0), -880);
        assert_eq!(animated_y(-880, 0, 0.5), -110);
        assert_eq!(animated_y(-880, 0, 1.0), 0);
        assert_eq!(animated_y(0, -1100, 0.5), -963);
    }

    #[test]
    fn auto_hide_waits_for_the_pointer_exit_delay() {
        let delay = WORKBENCH_INTERACTION.pointer_exit_collapse_duration(Platform::Windows);
        let start = Instant::now();
        let mut tracker = AutoHideTracker::new(delay);
        assert!(!tracker.update(start, true));
        assert!(!tracker.update(start, false));
        assert!(!tracker.update(start + delay - Duration::from_millis(1), false));
        assert!(tracker.update(start + delay, false));
        tracker.reset();
        assert!(!tracker.update(start + delay, false));
    }

    #[test]
    fn native_corner_radius_tracks_display_scale() {
        assert_eq!(window_region_radius(96), i32::from(PANEL_RADIUS));
        assert_eq!(window_region_radius(120), 28);
        assert_eq!(window_region_radius(144), 34);
    }

    #[test]
    fn top_overlay_centers_on_positive_and_negative_displays() {
        assert_eq!(centered_display_x(0, 2560, 1000), 780);
        assert_eq!(centered_display_x(-2560, 2560, 1200), -1880);
        assert_eq!(centered_display_x(0, 800, 1000), 0);
    }

    #[test]
    fn dwell_and_cooldown_gate_the_trigger() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, false, true));
        assert!(!trigger.update(start + Duration::from_millis(179), false, true));
        assert!(trigger.update(start + trigger_dwell(), false, true));
        assert!(!trigger.update(start + trigger_dwell(), false, true));
    }

    #[test]
    fn cooldown_blocks_an_early_reentry() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, false, true));
        assert!(trigger.update(start + trigger_dwell(), false, true));
        assert!(!trigger.update(start + trigger_dwell(), false, false));
        let early = start + trigger_dwell() + trigger_cooldown() - Duration::from_millis(1);
        assert!(!trigger.update(early, false, true));
        assert!(!trigger.update(early + trigger_dwell(), false, true));
    }

    #[test]
    fn pointer_must_leave_and_return_before_rearming() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, false, true));
        assert!(trigger.update(start + trigger_dwell(), false, true));
        let after_cooldown = start + trigger_dwell() + trigger_cooldown();
        assert!(!trigger.update(after_cooldown, false, true));
        assert!(!trigger.update(after_cooldown, false, false));
        assert!(!trigger.update(after_cooldown, false, true));
        assert!(trigger.update(after_cooldown + trigger_dwell(), false, true));
    }

    #[test]
    fn disabled_trigger_never_fires() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(false);
        assert!(!trigger.update(start, false, true));
        assert!(!trigger.update(start + trigger_dwell(), false, true));
    }

    #[test]
    fn visible_window_never_triggers() {
        let start = Instant::now();
        let mut trigger = TopEdgeTrigger::new(true);
        assert!(!trigger.update(start, true, true));
        assert!(!trigger.update(start + trigger_dwell(), true, true));
    }
}
