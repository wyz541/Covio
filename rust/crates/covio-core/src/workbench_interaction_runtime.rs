//! Runtime helpers derived from the macOS Workbench interaction contract.

use crate::workbench_interaction::{EasingSpec, Platform, WORKBENCH_INTERACTION};

/// A display rectangle in virtual-screen coordinates.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DisplayRect {
    pub left: f64,
    pub top: f64,
    pub width: f64,
    pub height: f64,
}

/// The resolved top-edge trigger rectangle.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TriggerBounds {
    pub left: f64,
    pub right: f64,
    pub top: f64,
    pub bottom: f64,
}

impl TriggerBounds {
    /// Returns whether a point is inside the top-edge trigger.
    #[must_use]
    pub fn contains(self, x: f64, y: f64) -> bool {
        x >= self.left && x < self.right && y >= self.top && y < self.bottom
    }
}

fn required_override(platform: Platform, field: &str) -> f64 {
    WORKBENCH_INTERACTION
        .platform_value(platform, field)
        .unwrap_or_else(|| panic!("missing Workbench interaction override: {field}"))
}

/// Returns the top-edge trigger bounds for one platform and display.
#[must_use]
pub fn trigger_bounds(platform: Platform, display: DisplayRect) -> TriggerBounds {
    let half_width_percent =
        required_override(platform, "trigger.geometry.centeredHalfWidthPercent");
    let edge_thickness = required_override(platform, "trigger.geometry.topEdgeThicknessPixels");
    let left = display.left + display.width * (50.0 - half_width_percent) / 100.0;
    let right = display.left + display.width * (50.0 + half_width_percent) / 100.0;
    let bottom = display.top + edge_thickness.min(display.height);
    TriggerBounds {
        left,
        right,
        top: display.top,
        bottom,
    }
}

/// Returns whether a point is inside the top-edge trigger.
#[must_use]
pub fn trigger_contains(platform: Platform, display: DisplayRect, x: f64, y: f64) -> bool {
    trigger_bounds(platform, display).contains(x, y)
}

/// Evaluates one contract easing curve at normalized time.
#[must_use]
pub fn transition_progress(easing: EasingSpec, duration_seconds: f64, normalized_time: f64) -> f64 {
    let time = normalized_time.clamp(0.0, 1.0);
    if time <= 0.0 {
        return 0.0;
    }
    if time >= 1.0 {
        return 1.0;
    }
    match easing {
        EasingSpec::EaseOut => 1.0 - (1.0 - time).powi(3),
        EasingSpec::Spring {
            response_seconds,
            damping_fraction,
        } => spring_progress(response_seconds, damping_fraction, time * duration_seconds),
    }
}

fn spring_progress(response_seconds: f64, damping_fraction: f64, time: f64) -> f64 {
    let angular_frequency = 2.0 * std::f64::consts::PI / response_seconds;
    let decay = (-damping_fraction * angular_frequency * time).exp();
    if damping_fraction < 1.0 {
        let damped_frequency = angular_frequency * (1.0 - damping_fraction.powi(2)).sqrt();
        let cosine = (damped_frequency * time).cos();
        let sine = (damped_frequency * time).sin();
        1.0 - decay * (cosine + damping_fraction * angular_frequency / damped_frequency * sine)
    } else {
        1.0 - decay * (1.0 + angular_frequency * time)
    }
}
