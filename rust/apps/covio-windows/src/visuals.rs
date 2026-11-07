//! Shared Windows visual tokens and egui primitives.

use eframe::egui::{
    self, Button, Color32, CornerRadius, FontData, FontDefinitions, FontFamily, FontId, Frame,
    Margin, Shadow, Stroke, TextStyle, Vec2, Visuals,
};
use std::sync::Arc;

/// Large card radius from the design contract.
pub(crate) const CARD_RADIUS: u8 = 16;
/// Hub panel radius from the design contract.
pub(crate) const PANEL_RADIUS: u8 = 22;
/// Shared control radius from the design contract.
pub(crate) const CONTROL_RADIUS: u8 = 12;
/// Maximum readable content width.
pub(crate) const PAGE_MAX_WIDTH: f32 = 1120.0;

const fn rgb(value: u32) -> Color32 {
    Color32::from_rgb(
        ((value >> 16) & 0xff) as u8,
        ((value >> 8) & 0xff) as u8,
        (value & 0xff) as u8,
    )
}

const fn rgba(value: u32, alpha: u8) -> Color32 {
    let [r, g, b, _] = rgb(value).to_array();
    Color32::from_rgba_premultiplied(r, g, b, alpha)
}

/// Semantic visual tokens used by the Windows egui host.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct CovioTheme {
    pub(crate) dark: bool,
    pub(crate) canvas: Color32,
    pub(crate) chrome: Color32,
    pub(crate) surface: Color32,
    pub(crate) surface_muted: Color32,
    pub(crate) surface_hover: Color32,
    pub(crate) surface_pressed: Color32,
    pub(crate) text_primary: Color32,
    pub(crate) text_secondary: Color32,
    pub(crate) text_disabled: Color32,
    pub(crate) accent: Color32,
    pub(crate) action_text: Color32,
    pub(crate) text_on_accent: Color32,
    pub(crate) separator: Color32,
    pub(crate) success: Color32,
    pub(crate) warning: Color32,
    pub(crate) error: Color32,
    pub(crate) shadow: Color32,
}

impl CovioTheme {
    /// Resolves the light or dark token set.
    pub(crate) fn from_dark(dark: bool) -> Self {
        if dark {
            Self {
                dark,
                canvas: rgb(0x1c1c1e),
                chrome: rgb(0x2c2c2e),
                surface: rgb(0x2c2c2e),
                surface_muted: rgb(0x242426),
                surface_hover: rgb(0x48484a),
                surface_pressed: rgb(0x545456),
                text_primary: rgb(0xf5f5f7),
                text_secondary: rgb(0xaeaeb2),
                text_disabled: rgb(0x98989d),
                accent: rgb(0x0a84ff),
                action_text: rgb(0x4da3ff),
                text_on_accent: Color32::WHITE,
                separator: rgb(0x3a3a3c),
                success: rgb(0x6edb84),
                warning: rgb(0xffb340),
                error: rgb(0xff6961),
                shadow: rgba(0x000000, 89),
            }
        } else {
            Self {
                dark,
                canvas: rgb(0xf2f2f7),
                chrome: rgb(0xf5f5f7),
                surface: Color32::WHITE,
                surface_muted: rgb(0xf7f7f9),
                surface_hover: rgb(0xf0f0f2),
                surface_pressed: rgb(0xe5e5ea),
                text_primary: rgb(0x1d1d1f),
                text_secondary: rgb(0x6e6e73),
                text_disabled: rgb(0x98989d),
                accent: rgb(0x007aff),
                action_text: rgb(0x0066cc),
                text_on_accent: Color32::WHITE,
                separator: rgb(0xd1d1d6),
                success: rgb(0x1e7a34),
                warning: rgb(0x8a4b00),
                error: rgb(0xd70015),
                shadow: rgba(0x000000, 46),
            }
        }
    }

    /// Installs fonts, metrics, and egui widget visuals.
    pub(crate) fn apply(self, context: &egui::Context) {
        install_windows_font(context);

        let mut visuals = if self.dark {
            Visuals::dark()
        } else {
            Visuals::light()
        };
        visuals.override_text_color = None;
        visuals.weak_text_color = Some(self.text_secondary);
        visuals.panel_fill = self.canvas;
        visuals.window_fill = self.surface;
        visuals.window_stroke = Stroke::new(1.0_f32, self.separator);
        visuals.window_corner_radius = CornerRadius::same(PANEL_RADIUS);
        visuals.menu_corner_radius = CornerRadius::same(CONTROL_RADIUS);
        visuals.window_shadow = self.shadow(12, 0, 2);
        visuals.popup_shadow = self.shadow(10, 0, 2);
        visuals.faint_bg_color = self.surface_muted;
        visuals.extreme_bg_color = self.surface;
        visuals.text_edit_bg_color = Some(self.surface);
        visuals.code_bg_color = self.surface_muted;
        visuals.hyperlink_color = self.action_text;
        visuals.warn_fg_color = self.warning;
        visuals.error_fg_color = self.error;
        visuals.selection.bg_fill = self.accent;
        visuals.selection.stroke = Stroke::new(1.0_f32, self.text_on_accent);
        visuals.widgets.noninteractive.bg_fill = self.surface;
        visuals.widgets.noninteractive.weak_bg_fill = self.surface;
        visuals.widgets.noninteractive.bg_stroke = Stroke::new(1.0_f32, self.separator);
        visuals.widgets.noninteractive.fg_stroke = Stroke::new(1.0_f32, self.text_secondary);
        visuals.widgets.noninteractive.corner_radius = CornerRadius::same(CARD_RADIUS);
        visuals.widgets.inactive.bg_fill = self.surface;
        visuals.widgets.inactive.weak_bg_fill = self.surface;
        visuals.widgets.inactive.bg_stroke = Stroke::new(1.0_f32, self.separator);
        visuals.widgets.inactive.fg_stroke = Stroke::new(1.0_f32, self.text_primary);
        visuals.widgets.inactive.corner_radius = CornerRadius::same(CONTROL_RADIUS);
        visuals.widgets.hovered.bg_fill = self.surface_hover;
        visuals.widgets.hovered.weak_bg_fill = self.surface_hover;
        visuals.widgets.hovered.bg_stroke = Stroke::new(1.0_f32, self.accent);
        visuals.widgets.hovered.fg_stroke = Stroke::new(1.0_f32, self.text_primary);
        visuals.widgets.hovered.corner_radius = CornerRadius::same(CONTROL_RADIUS);
        visuals.widgets.active.bg_fill = self.surface_pressed;
        visuals.widgets.active.weak_bg_fill = self.surface_pressed;
        visuals.widgets.active.bg_stroke = Stroke::new(1.0_f32, self.accent);
        visuals.widgets.active.fg_stroke = Stroke::new(1.0_f32, self.text_primary);
        visuals.widgets.active.corner_radius = CornerRadius::same(CONTROL_RADIUS);
        visuals.widgets.open = visuals.widgets.active;
        context.set_visuals(visuals);

        context.style_mut(|style| {
            style.animation_time = 0.16;
            style.spacing.item_spacing = Vec2::new(8.0, 8.0);
            style.spacing.button_padding = Vec2::new(12.0, 7.0);
            style.spacing.interact_size = Vec2::new(36.0, 32.0);
            style.spacing.window_margin = Margin::same(16);
            style.spacing.menu_margin = Margin::same(8);
            style.spacing.scroll = egui::style::ScrollStyle::thin();
            style.text_styles = [
                (
                    TextStyle::Heading,
                    FontId::new(24.0, FontFamily::Proportional),
                ),
                (TextStyle::Body, FontId::new(14.0, FontFamily::Proportional)),
                (
                    TextStyle::Button,
                    FontId::new(13.0, FontFamily::Proportional),
                ),
                (
                    TextStyle::Small,
                    FontId::new(11.5, FontFamily::Proportional),
                ),
                (
                    TextStyle::Monospace,
                    FontId::new(12.0, FontFamily::Monospace),
                ),
            ]
            .into();
        });
    }

    pub(crate) fn card_frame(self) -> Frame {
        Frame::new()
            .fill(self.surface)
            .stroke(Stroke::new(1.0_f32, self.separator))
            .corner_radius(CornerRadius::same(CARD_RADIUS))
            .inner_margin(Margin::same(16))
            .shadow(self.shadow(8, 0, 1))
    }

    pub(crate) fn muted_frame(self) -> Frame {
        Frame::new()
            .fill(self.surface_muted)
            .stroke(Stroke::new(1.0_f32, self.separator))
            .corner_radius(CornerRadius::same(CARD_RADIUS))
            .inner_margin(Margin::same(16))
    }

    pub(crate) fn toolbar_frame(self) -> Frame {
        Frame::new()
            .fill(self.chrome)
            .stroke(Stroke::new(1.0_f32, self.separator))
            .corner_radius(CornerRadius::same(CARD_RADIUS))
            .inner_margin(Margin::symmetric(14, 8))
            .shadow(self.shadow(6, 0, 1))
    }

    pub(crate) fn primary_button<'a>(self, text: impl Into<String>) -> Button<'a> {
        Button::new(egui::RichText::new(text).color(self.text_on_accent))
            .fill(self.accent)
            .stroke(Stroke::NONE)
            .corner_radius(CornerRadius::same(CONTROL_RADIUS))
            .min_size(Vec2::new(0.0, 32.0))
    }

    pub(crate) fn secondary_button<'a>(self, text: impl Into<String>) -> Button<'a> {
        Button::new(egui::RichText::new(text).color(self.text_primary))
            .fill(self.surface)
            .stroke(Stroke::new(1.0_f32, self.separator))
            .corner_radius(CornerRadius::same(CONTROL_RADIUS))
            .min_size(Vec2::new(0.0, 32.0))
    }

    pub(crate) fn destructive_button<'a>(self, text: impl Into<String>) -> Button<'a> {
        Button::new(egui::RichText::new(text).color(self.error))
            .fill(self.surface)
            .stroke(Stroke::new(1.0_f32, self.error))
            .corner_radius(CornerRadius::same(CONTROL_RADIUS))
            .min_size(Vec2::new(0.0, 32.0))
    }

    pub(crate) fn nav_button<'a>(
        self,
        text: impl Into<egui::WidgetText>,
        selected: bool,
    ) -> Button<'a> {
        Button::new(text)
            .selected(selected)
            .corner_radius(CornerRadius::same(CONTROL_RADIUS))
            .min_size(Vec2::new(72.0, 30.0))
    }

    fn shadow(self, blur: u8, x: i8, y: i8) -> Shadow {
        Shadow {
            offset: [x, y],
            blur,
            spread: 0,
            color: self.shadow,
        }
    }
}

fn install_windows_font(context: &egui::Context) {
    let Some(windir) = std::env::var_os("WINDIR") else {
        return;
    };
    let font_path = std::path::PathBuf::from(windir)
        .join("Fonts")
        .join("segoeui.ttf");
    let Ok(bytes) = std::fs::read(font_path) else {
        return;
    };
    let mut fonts = FontDefinitions::default();
    fonts.font_data.insert(
        "covio-segoe-ui".to_owned(),
        Arc::new(FontData::from_owned(bytes)),
    );
    fonts
        .families
        .entry(FontFamily::Proportional)
        .or_default()
        .insert(0, "covio-segoe-ui".to_owned());
    context.set_fonts(fonts);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn light_and_dark_tokens_match_the_contract() {
        let light = CovioTheme::from_dark(false);
        let dark = CovioTheme::from_dark(true);
        assert_eq!(light.canvas, rgb(0xf2f2f7));
        assert_eq!(dark.canvas, rgb(0x1c1c1e));
        assert_eq!(light.surface, Color32::WHITE);
        assert_eq!(dark.surface, rgb(0x2c2c2e));
        assert_eq!(light.accent, rgb(0x007aff));
        assert_eq!(dark.accent, rgb(0x0a84ff));
    }

    #[test]
    fn shared_radii_match_the_contract() {
        assert_eq!(CARD_RADIUS, 16);
        assert_eq!(PANEL_RADIUS, 22);
        assert_eq!(CONTROL_RADIUS, 12);
    }
}
