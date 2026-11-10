//! Shared Windows visual tokens and egui primitives.

use covio_core::contract_design;
use eframe::egui::{
    self, Button, Color32, CornerRadius, FontData, FontDefinitions, FontFamily, FontId, Frame,
    Margin, Shadow, Stroke, TextStyle, Vec2, Visuals,
};
use std::sync::Arc;

/// Large card radius from the macOS visual baseline.
pub(crate) const CARD_RADIUS: u8 = 16;
/// Hub panel radius from the macOS visual baseline.
pub(crate) const PANEL_RADIUS: u8 = 22;
/// Shared control radius from the macOS visual baseline.
pub(crate) const CONTROL_RADIUS: u8 = 8;
/// Workbench panel width from `HubMetrics.panelWidth`.
pub(crate) const HUB_PANEL_WIDTH: f32 = 960.0;
/// Workbench panel padding from `HubMetrics.panelPadding`.
pub(crate) const HUB_PANEL_PADDING: f32 = 24.0;
/// Workbench content width from `HubMetrics.contentColumnWidth`.
pub(crate) const HUB_CONTENT_WIDTH: f32 = HUB_PANEL_WIDTH - HUB_PANEL_PADDING * 2.0;
/// Workbench top bar height from `HubMetrics.tabBarHeight`.
pub(crate) const HUB_TAB_BAR_HEIGHT: f32 = 46.0;
/// Workbench search width from `HubMetrics.searchFieldWidth`.
pub(crate) const HUB_SEARCH_WIDTH: f32 = 190.0;
/// Workbench navigation control height from `HubMetrics.tabHeight`.
pub(crate) const HUB_NAV_HEIGHT: f32 = 30.0;
/// Workbench tab width from `HubMetrics.tabWidth`.
pub(crate) const HUB_TAB_WIDTH: f32 = 72.0;
/// Workbench home action width from `HubMetrics.homeEntryWidth`.
pub(crate) const HUB_HOME_WIDTH: f32 = 52.0;
/// Workbench page action width from `HubMetrics.actionButtonMinWidth`.
pub(crate) const HUB_ACTION_WIDTH: f32 = 52.0;
/// Workbench top bar item gap from `HubMetrics.tabBarItemGap`.
pub(crate) const HUB_ITEM_GAP: f32 = 8.0;
/// Workbench tab gap from `HubMetrics.tabGap`.
pub(crate) const HUB_TAB_GAP: f32 = 4.0;
/// Bento column count from `HubMetrics.bentoColumns`.
pub(crate) const BENTO_COLUMNS: usize = 4;
/// Bento row height from `HubMetrics.bentoRowHeight`.
pub(crate) const BENTO_ROW_HEIGHT: f32 = 96.0;
/// Bento grid gap from `HubMetrics.bentoGap`.
pub(crate) const BENTO_GAP: f32 = 12.0;
/// Bento card padding from `HubMetrics.bentoCardPadding`.
pub(crate) const BENTO_CARD_PADDING: f32 = 14.0;
/// Bento grid maximum rows in the default Workbench layout.
pub(crate) const BENTO_MAX_ROWS: usize = 4;
/// Settings content width from the macOS settings search overlay.
pub(crate) const SETTINGS_CONTENT_WIDTH: f32 = 620.0;
/// Settings toolbar height aligned with the macOS Settings window.
pub(crate) const SETTINGS_TOOLBAR_HEIGHT: f32 = 54.0;
/// Settings grouped-form row height.
pub(crate) const SETTINGS_ROW_HEIGHT: f32 = 44.0;
/// Maximum readable content width.
pub(crate) const PAGE_MAX_WIDTH: f32 = HUB_CONTENT_WIDTH;

/// Warm dashboard tint.
pub(crate) const WIDGET_TINT_AMBER: Color32 = rgb(0xfff2bd);
/// Green dashboard tint.
pub(crate) const WIDGET_TINT_MINT: Color32 = rgb(0xe5f8ea);
/// Blue dashboard tint.
pub(crate) const WIDGET_TINT_SKY: Color32 = rgb(0xdde7f8);
/// Rose dashboard tint.
pub(crate) const WIDGET_TINT_ROSE: Color32 = rgb(0xffe8ea);
/// Apricot dashboard tint.
pub(crate) const WIDGET_TINT_APRICOT: Color32 = rgb(0xfff1dd);
/// Cool neutral dashboard tint.
pub(crate) const WIDGET_TINT_SLATE: Color32 = rgb(0xe9edf5);

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
            style.spacing.button_padding = Vec2::new(10.0, 5.0);
            style.spacing.interact_size = Vec2::new(36.0, 30.0);
            style.spacing.window_margin = Margin::same(16);
            style.spacing.menu_margin = Margin::same(8);
            style.spacing.scroll = egui::style::ScrollStyle::thin();
            style.text_styles = [
                (
                    TextStyle::Heading,
                    FontId::new(
                        typography_size("typography/section-title", 20.0),
                        FontFamily::Proportional,
                    ),
                ),
                (
                    TextStyle::Body,
                    FontId::new(
                        typography_size("typography/body", 13.0),
                        FontFamily::Proportional,
                    ),
                ),
                (
                    TextStyle::Button,
                    FontId::new(
                        typography_size("typography/action", 12.0),
                        FontFamily::Proportional,
                    ),
                ),
                (
                    TextStyle::Small,
                    FontId::new(
                        typography_size("typography/caption", 11.0),
                        FontFamily::Proportional,
                    ),
                ),
                (
                    TextStyle::Monospace,
                    FontId::new(11.0, FontFamily::Monospace),
                ),
            ]
            .into();
        });
    }

    pub(crate) fn widget_fill(self, tint: Color32) -> Color32 {
        let [r, g, b, _] = tint.to_array();
        Color32::from_rgba_unmultiplied(r, g, b, 26)
    }

    pub(crate) fn workbench_plate_frame(self) -> Frame {
        Frame::new()
            .fill(if self.dark {
                self.chrome
            } else {
                Color32::WHITE
            })
            .stroke(Stroke::new(1.0_f32, self.separator))
            .corner_radius(CornerRadius::same(PANEL_RADIUS))
    }

    pub(crate) fn settings_shell_frame(self) -> Frame {
        Frame::new()
            .fill(self.canvas)
            .stroke(Stroke::new(1.0_f32, self.separator))
            .corner_radius(CornerRadius::same(PANEL_RADIUS))
    }

    pub(crate) fn settings_group_frame(self) -> Frame {
        Frame::new()
            .fill(if self.dark { self.surface } else { self.chrome })
            .corner_radius(CornerRadius::same(CARD_RADIUS))
            .inner_margin(Margin::symmetric(16, 2))
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
    let Some(font) = contract_design::platform_font("windows", "interface") else {
        return;
    };
    for file_name in font.file_names {
        let font_path = std::path::PathBuf::from(&windir)
            .join("Fonts")
            .join(file_name);
        let Ok(bytes) = std::fs::read(font_path) else {
            continue;
        };
        let mut fonts = FontDefinitions::default();
        fonts.font_data.insert(
            "covio-windows-interface-font".to_owned(),
            Arc::new(FontData::from_owned(bytes)),
        );
        fonts
            .families
            .entry(FontFamily::Proportional)
            .or_default()
            .insert(0, "covio-windows-interface-font".to_owned());
        context.set_fonts(fonts);
        return;
    }
}

fn typography_size(key: &str, fallback: f32) -> f32 {
    contract_design::typography_token(key).map_or(fallback, |token| token.size)
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
    fn outer_shells_keep_rounded_corners_without_drop_shadows() {
        let theme = CovioTheme::from_dark(false);
        let workbench = theme.workbench_plate_frame();
        assert_eq!(workbench.corner_radius, CornerRadius::same(PANEL_RADIUS));
        assert_eq!(workbench.shadow.blur, 0);
        assert_eq!(workbench.shadow.spread, 0);

        let settings = theme.settings_shell_frame();
        assert_eq!(settings.corner_radius, CornerRadius::same(PANEL_RADIUS));
        assert_eq!(settings.shadow.blur, 0);
        assert_eq!(settings.shadow.spread, 0);
    }

    #[test]
    fn shared_radii_match_the_contract() {
        assert_eq!(CARD_RADIUS, 16);
        assert_eq!(PANEL_RADIUS, 22);
        assert_eq!(CONTROL_RADIUS, 8);
    }

    #[test]
    fn windows_font_mapping_uses_the_generated_contract() {
        let font = contract_design::platform_font("windows", "interface").expect("Windows font");
        assert_eq!(font.family, "Segoe UI Variable");
        assert_eq!(font.file_names.first().copied(), Some("SegUIVar.ttf"));
        assert!(!font.platforms.contains(&"macos"));
    }

    #[test]
    fn windows_typography_sizes_come_from_the_generated_contract() {
        assert_eq!(typography_size("typography/body", -1.0), 13.0);
        assert_eq!(typography_size("typography/action", -1.0), 12.0);
        assert_eq!(typography_size("typography/caption", -1.0), 11.0);
    }
}
