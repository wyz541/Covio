//! Windows-only egui composition root.

use covio_core::AppConfig;
use covio_platform::WindowsAppDataDirectory;
use covio_windows::{
    CloseDisposition, CoreRuntime, HostModel, HostStatus, HostView, ThemePreference,
    WindowsDataPaths, now_epoch_seconds,
};
use eframe::egui;
use eframe::egui_wgpu::{WgpuConfiguration, WgpuSetup, WgpuSetupCreateNew};
use eframe::wgpu;
use serde_json::json;
use single_instance::SingleInstance;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tray_icon::menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem};
use tray_icon::{TrayIcon, TrayIconBuilder, TrayIconEvent};

const INSTANCE_NAME: &str = "Local\\com.wyz.covio.windows";

/// Runs the Windows host.
pub fn run() -> Result<(), String> {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments
        .iter()
        .any(|argument| argument == "--single-instance-secondary")
    {
        let instance = SingleInstance::new(INSTANCE_NAME).map_err(|error| error.to_string())?;
        if instance.is_single() {
            return Err("secondary single-instance probe became the primary instance".to_owned());
        }
        return Ok(());
    }
    if arguments
        .iter()
        .any(|argument| argument == "--single-instance-smoke")
    {
        return run_single_instance_smoke();
    }

    let instance = SingleInstance::new(INSTANCE_NAME).map_err(|error| error.to_string())?;
    if !instance.is_single() {
        return Ok(());
    }

    let data_root = data_root_from_arguments(&arguments)?;
    let core = WindowsDataPaths::new(data_root).app_core();
    let start_hidden = arguments.iter().any(|argument| argument == "--background");
    let initial_theme = theme_from_arguments(&arguments);
    let screenshot_path = screenshot_path_from_arguments(&arguments);
    let auto_exit_frames = arguments
        .iter()
        .any(|argument| argument == "--window-smoke")
        .then_some(8_u32);
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Covio")
            .with_inner_size([980.0, 720.0])
            .with_min_inner_size([640.0, 480.0])
            .with_visible(!start_hidden),
        renderer: eframe::Renderer::Wgpu,
        wgpu_options: wgpu_configuration(),
        ..Default::default()
    };

    eframe::run_native(
        "Covio",
        options,
        Box::new(move |creation_context| {
            Ok(Box::new(CovioWindowsApp::new(
                creation_context,
                core,
                start_hidden,
                auto_exit_frames,
                initial_theme,
                screenshot_path,
            )))
        }),
    )
    .map_err(|error| error.to_string())
}

struct CovioWindowsApp {
    core: CoreRuntime,
    model: HostModel,
    tray: Option<TrayController>,
    tray_error: Option<String>,
    draft_config: Option<AppConfig>,
    needs_refresh: bool,
    auto_exit_frames: Option<u32>,
    screenshot_path: Option<PathBuf>,
    screenshot_requested: bool,
    rendered_frames: u32,
}

impl CovioWindowsApp {
    fn new(
        creation_context: &eframe::CreationContext<'_>,
        core: covio_ffi::AppCore,
        start_hidden: bool,
        auto_exit_frames: Option<u32>,
        initial_theme: ThemePreference,
        screenshot_path: Option<PathBuf>,
    ) -> Self {
        let mut model = HostModel::new(initial_theme, false);
        if start_hidden {
            model.hide();
        }
        let (tray, tray_error) = match TrayController::new() {
            Ok(tray) => (Some(tray), None),
            Err(error) => (None, Some(error)),
        };
        let mut app = Self {
            core: CoreRuntime::new(core),
            model,
            tray,
            tray_error,
            draft_config: None,
            needs_refresh: true,
            auto_exit_frames,
            screenshot_path,
            screenshot_requested: false,
            rendered_frames: 0,
        };
        app.apply_visuals(&creation_context.egui_ctx);
        app.load_initial_snapshot();
        app
    }

    fn load_initial_snapshot(&mut self) {
        let request_id = match self.core.request_snapshot(now_epoch_seconds()) {
            Ok(request_id) => request_id,
            Err(error) => {
                self.model.set_error(error);
                return;
            }
        };
        if !self.model.begin_request(request_id) {
            let _ = self.core.cancel(request_id);
            return;
        }
        if let Some(response) = self
            .core
            .wait_for_response(request_id, Duration::from_secs(2))
        {
            self.model.apply_response(response);
        }
    }

    fn refresh_snapshot(&mut self) {
        if self.model.pending_request().is_some() {
            return;
        }
        match self.core.request_snapshot(now_epoch_seconds()) {
            Ok(request_id) => {
                if !self.model.begin_request(request_id) {
                    let _ = self.core.cancel(request_id);
                }
            }
            Err(error) => self.model.set_error(error),
        }
    }

    fn save_config(&mut self, config: AppConfig) {
        if self.model.pending_request().is_some() {
            return;
        }
        match self.core.request(
            "config.save",
            json!({"config": config}),
            now_epoch_seconds(),
        ) {
            Ok(request_id) => {
                if !self.model.begin_request(request_id) {
                    let _ = self.core.cancel(request_id);
                }
            }
            Err(error) => self.model.set_error(error),
        }
    }

    fn poll_core(&mut self) {
        while let Some(response) = self.core.try_response() {
            let command = response.command.clone();
            if self.model.apply_response(response) && command == "config.save" {
                self.draft_config = None;
                self.needs_refresh = true;
            }
        }
        if self.needs_refresh && self.model.pending_request().is_none() {
            self.needs_refresh = false;
            self.refresh_snapshot();
        }
    }

    fn poll_tray(&mut self, context: &egui::Context) {
        let mut actions = Vec::new();
        if let Some(tray) = &self.tray {
            while let Some(action) = tray.poll() {
                actions.push(action);
            }
        }
        for action in actions {
            match action {
                TrayAction::OpenHome => {
                    self.model.show_home();
                    show_window(context);
                }
                TrayAction::OpenSettings => {
                    self.model.show_settings();
                    show_window(context);
                }
                TrayAction::ToggleWindow => {
                    self.model.toggle_from_tray();
                    if self.model.is_visible() {
                        show_window(context);
                    } else {
                        hide_window(context);
                    }
                }
                TrayAction::Quit => {
                    self.model.begin_exit();
                    self.core.shutdown();
                    context.send_viewport_cmd(egui::ViewportCommand::Close);
                }
            }
        }
    }

    fn handle_keyboard(&mut self, context: &egui::Context) {
        if context.input_mut(|input| input.consume_key(egui::Modifiers::CTRL, egui::Key::Comma)) {
            self.model.show_settings();
            show_window(context);
        }
        if context.input_mut(|input| input.consume_key(egui::Modifiers::CTRL, egui::Key::R)) {
            self.refresh_snapshot();
        }
        if context.input_mut(|input| input.consume_key(egui::Modifiers::NONE, egui::Key::Escape)) {
            self.model.hide();
            hide_window(context);
        }
    }

    fn handle_close(&mut self, context: &egui::Context) {
        if !context.input(|input| input.viewport().close_requested()) {
            return;
        }
        match self.model.close_disposition() {
            CloseDisposition::Hide => {
                context.send_viewport_cmd(egui::ViewportCommand::CancelClose);
                hide_window(context);
            }
            CloseDisposition::Exit => self.core.shutdown(),
        }
    }

    fn apply_visuals(&self, context: &egui::Context) {
        let dark = match self.model.theme() {
            ThemePreference::System => dark_light::detect() == dark_light::Mode::Dark,
            ThemePreference::Light => false,
            ThemePreference::Dark => true,
        };
        context.set_visuals(if dark {
            egui::Visuals::dark()
        } else {
            egui::Visuals::light()
        });
        context.style_mut(|style| {
            style.animation_time = if self.model.reduced_motion() {
                0.0
            } else {
                0.16
            };
        });
    }

    fn home_view(&mut self, ui: &mut egui::Ui) {
        ui.heading("Covio");
        ui.label("Rust core running in the Windows host.");
        if let Some(error) = &self.tray_error {
            ui.colored_label(egui::Color32::from_rgb(154, 86, 0), error);
        }
        ui.add_space(12.0);

        let snapshot = self.model.snapshot().cloned();
        if let Some(snapshot) = snapshot {
            egui::Grid::new("core-state-grid")
                .num_columns(2)
                .spacing([24.0, 10.0])
                .show(ui, |ui| {
                    ui.label("Screenshot shelf");
                    ui.monospace(snapshot.shelf_item_count.to_string());
                    ui.end_row();
                    ui.label("Clipboard history");
                    ui.monospace(snapshot.clipboard_item_count.to_string());
                    ui.end_row();
                    ui.label("Workspace");
                    ui.monospace(snapshot.workspace_entry_count.to_string());
                    ui.end_row();
                    ui.label("Loaded at");
                    ui.monospace(snapshot.loaded_at_epoch_seconds.to_string());
                    ui.end_row();
                });
        } else {
            ui.spinner();
        }

        ui.add_space(16.0);
        ui.horizontal(|ui| {
            if ui.button("Refresh").clicked() {
                self.refresh_snapshot();
            }
            if ui.button("Settings").clicked() {
                self.model.show_settings();
            }
        });
    }

    fn settings_view(&mut self, ui: &mut egui::Ui) {
        ui.label("These settings are stored by the Rust core.");
        ui.label("Windows capability adapters are connected by #607 and #608.");
        ui.add_space(12.0);

        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        let draft = self
            .draft_config
            .get_or_insert_with(|| AppConfig::from_json_value(&snapshot.config));
        ui.checkbox(&mut draft.launch_at_login, "Launch at login preference");
        ui.checkbox(&mut draft.clipboard_enabled, "Capture clipboard history");
        ui.checkbox(&mut draft.notifications_enabled, "Show notifications");
        ui.checkbox(&mut draft.update_check_enabled, "Check for updates");

        ui.add_space(12.0);
        ui.separator();
        ui.label("Appearance");
        ui.horizontal(|ui| {
            if ui
                .selectable_label(self.model.theme() == ThemePreference::System, "System")
                .clicked()
            {
                self.model.set_theme(ThemePreference::System);
            }
            if ui
                .selectable_label(self.model.theme() == ThemePreference::Light, "Light")
                .clicked()
            {
                self.model.set_theme(ThemePreference::Light);
            }
            if ui
                .selectable_label(self.model.theme() == ThemePreference::Dark, "Dark")
                .clicked()
            {
                self.model.set_theme(ThemePreference::Dark);
            }
        });
        let mut reduced_motion = self.model.reduced_motion();
        if ui.checkbox(&mut reduced_motion, "Reduce motion").changed() {
            self.model.set_reduced_motion(reduced_motion);
        }

        ui.add_space(16.0);
        let save = ui.button("Save").clicked();
        let config = draft.clone();
        if save {
            self.save_config(config);
        }

        if self.tray.is_none() {
            ui.colored_label(
                egui::Color32::from_rgb(154, 86, 0),
                self.tray_error
                    .as_deref()
                    .unwrap_or("Windows tray is unavailable."),
            );
        }
    }

    fn render_status(&self, ui: &mut egui::Ui) {
        match self.model.status() {
            HostStatus::Idle => {}
            HostStatus::Loading => {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label("Loading core state...");
                });
            }
            HostStatus::Ready => {
                ui.label("Core state is current.");
            }
            HostStatus::Error(message) => {
                ui.colored_label(egui::Color32::from_rgb(180, 54, 54), message);
            }
        }
    }
}

impl eframe::App for CovioWindowsApp {
    fn update(&mut self, context: &egui::Context, _frame: &mut eframe::Frame) {
        self.rendered_frames = self.rendered_frames.saturating_add(1);
        if self.capture_screenshot(context) {
            return;
        }
        if self
            .auto_exit_frames
            .is_some_and(|limit| self.rendered_frames >= limit)
        {
            if let Some(error) = &self.tray_error {
                eprintln!("Windows tray smoke failed: {error}");
                std::process::exit(1);
            }
            self.model.begin_exit();
            self.core.shutdown();
            context.send_viewport_cmd(egui::ViewportCommand::Close);
            return;
        }

        context.request_repaint_after(Duration::from_millis(100));
        self.poll_tray(context);
        self.poll_core();
        self.handle_keyboard(context);
        self.handle_close(context);
        self.apply_visuals(context);

        if !self.model.is_visible() {
            return;
        }

        egui::TopBottomPanel::top("navigation").show(context, |ui| {
            ui.horizontal(|ui| {
                ui.heading("Covio");
                ui.separator();
                if ui
                    .selectable_label(self.model.view() == HostView::Home, "Home")
                    .clicked()
                {
                    self.model.select_view(HostView::Home);
                }
                if ui
                    .selectable_label(self.model.view() == HostView::Settings, "Settings")
                    .clicked()
                {
                    self.model.select_view(HostView::Settings);
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if ui.button("Hide").clicked() {
                        self.model.hide();
                        hide_window(context);
                    }
                });
            });
        });

        egui::CentralPanel::default().show(context, |ui| {
            self.render_status(ui);
            ui.add_space(8.0);
            self.home_view(ui);
        });

        if self.model.view() == HostView::Settings {
            let mut open = true;
            egui::Window::new("Covio Settings")
                .open(&mut open)
                .collapsible(false)
                .resizable(true)
                .default_width(520.0)
                .show(context, |ui| self.settings_view(ui));
            if !open {
                self.model.select_view(HostView::Home);
            }
        }

        if self.screenshot_path.is_some()
            && !self.screenshot_requested
            && self.rendered_frames >= 3
            && self.model.snapshot().is_some()
        {
            self.screenshot_requested = true;
            context.send_viewport_cmd(egui::ViewportCommand::Screenshot(egui::UserData::default()));
        }
    }

    fn on_exit(&mut self) {
        self.core.shutdown();
    }
}

impl CovioWindowsApp {
    fn capture_screenshot(&mut self, context: &egui::Context) -> bool {
        let Some(path) = &self.screenshot_path else {
            return false;
        };
        let screenshot = context.input(|input| {
            input.events.iter().find_map(|event| {
                if let egui::Event::Screenshot { image, .. } = event {
                    Some(Arc::clone(image))
                } else {
                    None
                }
            })
        });
        let Some(image) = screenshot else {
            return false;
        };
        let width = image.size[0] as u32;
        let height = image.size[1] as u32;
        let mut rgba = Vec::with_capacity(image.pixels.len() * 4);
        for pixel in &image.pixels {
            rgba.extend_from_slice(&pixel.to_array());
        }
        if let Some(parent) = path.parent() {
            if let Err(error) = std::fs::create_dir_all(parent) {
                eprintln!("Cannot create Windows screenshot directory: {error}");
                std::process::exit(1);
            }
        }
        if let Err(error) = image::save_buffer(path, &rgba, width, height, image::ColorType::Rgba8)
        {
            eprintln!("Cannot save Windows host screenshot: {error}");
            std::process::exit(1);
        }
        println!("Windows host screenshot saved.");
        self.model.begin_exit();
        self.core.shutdown();
        context.send_viewport_cmd(egui::ViewportCommand::Close);
        true
    }
}

fn show_window(context: &egui::Context) {
    context.send_viewport_cmd(egui::ViewportCommand::Visible(true));
    context.send_viewport_cmd(egui::ViewportCommand::Focus);
}

fn hide_window(context: &egui::Context) {
    context.send_viewport_cmd(egui::ViewportCommand::Visible(false));
}

fn wgpu_configuration() -> WgpuConfiguration {
    let mut setup = WgpuSetupCreateNew::default();
    setup.instance_descriptor.backends = wgpu::Backends::DX12;
    setup.native_adapter_selector = Some(Arc::new(|adapters, surface| {
        adapters
            .iter()
            .find(|adapter| {
                adapter.get_info().device_type == wgpu::DeviceType::Cpu
                    && surface.is_none_or(|surface| adapter.is_surface_supported(surface))
            })
            .or_else(|| {
                adapters.iter().find(|adapter| {
                    surface.is_none_or(|surface| adapter.is_surface_supported(surface))
                })
            })
            .cloned()
            .ok_or_else(|| "no DX12 surface-compatible adapter".to_owned())
    }));
    WgpuConfiguration {
        wgpu_setup: WgpuSetup::CreateNew(setup),
        ..Default::default()
    }
}

fn screenshot_path_from_arguments(arguments: &[String]) -> Option<PathBuf> {
    arguments
        .iter()
        .position(|argument| argument == "--screenshot")
        .and_then(|index| arguments.get(index + 1))
        .map(PathBuf::from)
}

fn theme_from_arguments(arguments: &[String]) -> ThemePreference {
    let value = arguments
        .iter()
        .position(|argument| argument == "--theme")
        .and_then(|index| arguments.get(index + 1))
        .map(String::as_str);
    match value {
        Some("light") => ThemePreference::Light,
        Some("dark") => ThemePreference::Dark,
        _ => ThemePreference::System,
    }
}

fn data_root_from_arguments(arguments: &[String]) -> Result<PathBuf, String> {
    if let Some(index) = arguments.iter().position(|value| value == "--data-dir") {
        if let Some(path) = arguments.get(index + 1) {
            let path = PathBuf::from(path);
            if !path.is_absolute() {
                return Err("Windows data directory must be absolute".to_owned());
            }
            return Ok(path);
        }
    }
    if let Some(path) = std::env::var_os("COVIO_WINDOWS_DATA_ROOT") {
        let path = PathBuf::from(path);
        if !path.is_absolute() {
            return Err("Windows data directory must be absolute".to_owned());
        }
        return Ok(path);
    }
    WindowsAppDataDirectory::from_environment().map_err(|error| error.message().to_owned())
}

fn run_single_instance_smoke() -> Result<(), String> {
    let primary = SingleInstance::new(INSTANCE_NAME).map_err(|error| error.to_string())?;
    if !primary.is_single() {
        return Err("single-instance smoke could not acquire the primary lock".to_owned());
    }
    let executable = std::env::current_exe().map_err(|error| error.to_string())?;
    let secondary = std::process::Command::new(executable)
        .arg("--single-instance-secondary")
        .status()
        .map_err(|error| error.to_string())?;
    if !secondary.success() {
        return Err(format!("secondary instance exited with {secondary}"));
    }
    drop(primary);
    let replacement = SingleInstance::new(INSTANCE_NAME).map_err(|error| error.to_string())?;
    if !replacement.is_single() {
        return Err("single-instance lock was not released after the primary exited".to_owned());
    }
    println!(
        "{}",
        serde_json::json!({
            "primaryAcquired": true,
            "secondaryRejected": true,
            "lockReacquired": true,
        })
    );
    Ok(())
}

enum TrayAction {
    OpenHome,
    OpenSettings,
    ToggleWindow,
    Quit,
}

struct TrayController {
    _tray: TrayIcon,
    open_id: MenuId,
    settings_id: MenuId,
    quit_id: MenuId,
}

impl TrayController {
    fn new() -> Result<Self, String> {
        let menu = Menu::new();
        let open = MenuItem::with_id("open", "Open Covio", true, None);
        let settings = MenuItem::with_id("settings", "Settings", true, None);
        let separator = PredefinedMenuItem::separator();
        let quit = MenuItem::with_id("quit", "Quit Covio", true, None);
        menu.append_items(&[&open, &settings, &separator, &quit])
            .map_err(|error| error.to_string())?;
        let tray = TrayIconBuilder::new()
            .with_menu(Box::new(menu))
            .with_menu_on_left_click(false)
            .with_tooltip("Covio")
            .with_icon(tray_icon_image()?)
            .build()
            .map_err(|error| error.to_string())?;
        Ok(Self {
            _tray: tray,
            open_id: open.id().clone(),
            settings_id: settings.id().clone(),
            quit_id: quit.id().clone(),
        })
    }

    fn poll(&self) -> Option<TrayAction> {
        while let Ok(event) = MenuEvent::receiver().try_recv() {
            if event.id == self.open_id {
                return Some(TrayAction::OpenHome);
            }
            if event.id == self.settings_id {
                return Some(TrayAction::OpenSettings);
            }
            if event.id == self.quit_id {
                return Some(TrayAction::Quit);
            }
        }
        while let Ok(event) = TrayIconEvent::receiver().try_recv() {
            if matches!(
                event,
                TrayIconEvent::DoubleClick {
                    button: tray_icon::MouseButton::Left,
                    ..
                } | TrayIconEvent::Click {
                    button: tray_icon::MouseButton::Left,
                    button_state: tray_icon::MouseButtonState::Up,
                    ..
                }
            ) {
                return Some(TrayAction::ToggleWindow);
            }
        }
        None
    }
}

fn tray_icon_image() -> Result<tray_icon::Icon, String> {
    const SIZE: u32 = 32;
    let mut rgba = Vec::with_capacity((SIZE * SIZE * 4) as usize);
    let center = (SIZE as f32 - 1.0) / 2.0;
    for y in 0..SIZE {
        for x in 0..SIZE {
            let dx = x as f32 - center;
            let dy = y as f32 - center;
            let distance = (dx * dx + dy * dy).sqrt();
            let alpha = if distance <= 14.0 { 255 } else { 0 };
            let highlight = if distance < 7.0 { 235 } else { 76 };
            rgba.extend_from_slice(&[highlight, 122, 255, alpha]);
        }
    }
    tray_icon::Icon::from_rgba(rgba, SIZE, SIZE).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn single_instance_is_released_when_the_primary_guard_drops() {
        let name = format!("{INSTANCE_NAME}.test.{}", std::process::id());
        let primary = SingleInstance::new(&name).expect("primary instance");
        assert!(primary.is_single());
        let secondary = SingleInstance::new(&name).expect("secondary instance");
        assert!(!secondary.is_single());
        drop(primary);
        let replacement = SingleInstance::new(&name).expect("replacement instance");
        assert!(replacement.is_single());
    }

    #[test]
    fn windows_data_root_honors_an_explicit_argument() {
        let arguments = vec![
            "covio-windows.exe".to_owned(),
            "--data-dir".to_owned(),
            "C:\\CovioTest".to_owned(),
        ];
        assert_eq!(
            data_root_from_arguments(&arguments),
            Ok(PathBuf::from("C:\\CovioTest"))
        );
    }

    #[test]
    fn theme_argument_accepts_light_and_dark() {
        let light = vec![
            "covio-windows.exe".to_owned(),
            "--theme".to_owned(),
            "light".to_owned(),
        ];
        let dark = vec![
            "covio-windows.exe".to_owned(),
            "--theme".to_owned(),
            "dark".to_owned(),
        ];
        assert_eq!(theme_from_arguments(&light), ThemePreference::Light);
        assert_eq!(theme_from_arguments(&dark), ThemePreference::Dark);
    }
}
