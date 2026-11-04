//! Windows-only egui composition root.

use covio_core::AppConfig;
use covio_core::clipboard::ClipItem;
use covio_core::workspace::{WorkspaceState, suggested_text_name};
use covio_platform::{
    Clipboard, FilePicker, FilePickerRequest, NotificationRequest, Notifier, ScreenshotDirectory,
    StartupRegistration, StartupSpec, WindowsAppDataDirectory, WindowsPlatformAdapters,
};
use covio_windows::{
    CloseDisposition, CoreRuntime, HostModel, HostStatus, HostView, ThemePreference,
    WindowsDataPaths, now_epoch_seconds,
};
use eframe::egui;
use eframe::egui_wgpu::{WgpuConfiguration, WgpuSetup, WgpuSetupCreateNew};
use eframe::wgpu;
use serde_json::json;
use single_instance::SingleInstance;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tray_icon::menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem};
use tray_icon::{TrayIcon, TrayIconBuilder, TrayIconEvent};

const INSTANCE_NAME: &str = "Local\\com.wyz.covio.windows";
const RELEASES_URL: &str = "https://github.com/wyz541/kmp-Covio/releases";
const CURRENT_VERSION: &str = match option_env!("COVIO_RELEASE_ID") {
    Some(value) => value,
    None => env!("CARGO_PKG_VERSION"),
};

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
    if arguments
        .iter()
        .any(|argument| argument == "--seed-smoke-data")
    {
        covio_windows::seed_screenshot_smoke_data(&data_root)?;
    }
    let data_paths = WindowsDataPaths::new(data_root);
    let core = data_paths.app_core();
    let start_hidden = arguments.iter().any(|argument| argument == "--background");
    let initial_theme = theme_from_arguments(&arguments);
    let initial_view = view_from_arguments(&arguments);
    let ui_scale = ui_scale_from_arguments(&arguments);
    let window_position = window_position_from_arguments(&arguments);
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
            .with_position(window_position.unwrap_or([120.0, 120.0]))
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
                data_paths,
                LaunchOptions {
                    start_hidden,
                    auto_exit_frames,
                    initial_theme,
                    initial_view,
                    screenshot_path,
                    ui_scale,
                },
            )))
        }),
    )
    .map_err(|error| error.to_string())
}

struct LaunchOptions {
    start_hidden: bool,
    auto_exit_frames: Option<u32>,
    initial_theme: ThemePreference,
    initial_view: Option<HostView>,
    screenshot_path: Option<PathBuf>,
    ui_scale: Option<f32>,
}

struct CovioWindowsApp {
    core: CoreRuntime,
    data_paths: WindowsDataPaths,
    adapters: WindowsPlatformAdapters,
    model: HostModel,
    tray: Option<TrayController>,
    tray_error: Option<String>,
    draft_config: Option<AppConfig>,
    needs_refresh: bool,
    auto_exit_frames: Option<u32>,
    screenshot_path: Option<PathBuf>,
    screenshot_requested: bool,
    rendered_frames: u32,
    workspace_text: String,
    last_clipboard_text: Option<String>,
    next_clipboard_poll: Instant,
    screenshot_directory: Option<PathBuf>,
    known_screenshots: BTreeSet<PathBuf>,
    screenshot_scan_initialized: bool,
    next_screenshot_poll: Instant,
    local_message: Option<String>,
}

impl CovioWindowsApp {
    fn new(
        creation_context: &eframe::CreationContext<'_>,
        core: covio_ffi::AppCore,
        data_paths: WindowsDataPaths,
        options: LaunchOptions,
    ) -> Self {
        let mut model = HostModel::new(options.initial_theme, false);
        if let Some(view) = options.initial_view {
            model.select_view(view);
        }
        if options.start_hidden {
            model.hide();
        }
        let (tray, tray_error) = match TrayController::new() {
            Ok(tray) => (Some(tray), None),
            Err(error) => (None, Some(error)),
        };
        let adapters = WindowsPlatformAdapters::default();
        let screenshot_directory = adapters.screenshots.directory().ok();
        let mut app = Self {
            core: CoreRuntime::new(core),
            data_paths,
            adapters,
            model,
            tray,
            tray_error,
            draft_config: None,
            needs_refresh: true,
            auto_exit_frames: options.auto_exit_frames,
            screenshot_path: options.screenshot_path,
            screenshot_requested: false,
            rendered_frames: 0,
            workspace_text: String::new(),
            last_clipboard_text: None,
            next_clipboard_poll: Instant::now(),
            screenshot_directory,
            known_screenshots: BTreeSet::new(),
            screenshot_scan_initialized: false,
            next_screenshot_poll: Instant::now(),
            local_message: None,
        };
        if let Some(ui_scale) = options.ui_scale {
            creation_context.egui_ctx.set_pixels_per_point(ui_scale);
        }
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

    fn send_core_command(&mut self, command: &str, payload: serde_json::Value) {
        if self.model.pending_request().is_some() {
            self.local_message = Some("Wait for the current core request.".to_owned());
            return;
        }
        match self.core.request(command, payload, now_epoch_seconds()) {
            Ok(request_id) => {
                if !self.model.begin_request(request_id) {
                    let _ = self.core.cancel(request_id);
                }
            }
            Err(error) => self.model.set_error(error),
        }
    }

    fn save_config(&mut self, config: AppConfig) {
        let startup_spec = match std::env::current_exe() {
            Ok(executable) => {
                StartupSpec::new("Covio", executable).with_arguments(["--background"])
            }
            Err(_) => {
                self.model
                    .set_error("Cannot resolve the Covio executable for startup.");
                return;
            }
        };
        let startup_result = if config.launch_at_login {
            self.adapters.startup.enable(&startup_spec)
        } else {
            self.adapters.startup.disable(&startup_spec)
        };
        if let Err(error) = startup_result {
            self.local_message = Some(error.message().to_owned());
            return;
        }
        self.send_core_command("config.save", json!({"config": config}));
    }

    fn poll_core(&mut self) {
        while let Some(response) = self.core.try_response() {
            let command = response.command.clone();
            let succeeded = response.ok;
            let result = response.result.clone();
            if self.model.apply_response(response) {
                if command == "config.save" {
                    self.draft_config = None;
                }
                if succeeded && command != "host.snapshot" {
                    self.needs_refresh = true;
                    match command.as_str() {
                        "workspace.importFiles" => {
                            let imported = result
                                .get("imported")
                                .and_then(serde_json::Value::as_u64)
                                .unwrap_or(0);
                            self.local_message = Some(format!("Imported {imported} file(s)."));
                            if imported > 0 {
                                self.notify("Covio", "Files added to the workspace.");
                            }
                        }
                        "clipboard.captureText" => {
                            self.local_message = Some("Captured clipboard text.".to_owned());
                        }
                        _ => {}
                    }
                }
            }
        }
        if self.needs_refresh && self.model.pending_request().is_none() {
            self.needs_refresh = false;
            self.refresh_snapshot();
        }
    }

    fn poll_clipboard_capture(&mut self) {
        if Instant::now() < self.next_clipboard_poll {
            return;
        }
        self.next_clipboard_poll = Instant::now() + Duration::from_secs(1);
        let Some(snapshot) = self.model.snapshot() else {
            return;
        };
        let config = AppConfig::from_json_value(&snapshot.config);
        if !config.clipboard_enabled
            || snapshot.clipboard.paused
            || self.model.pending_request().is_some()
        {
            return;
        }
        let text = match self.adapters.clipboard.read_text() {
            Ok(Some(text)) if !text.trim().is_empty() => text,
            Ok(_) => return,
            Err(error) if error.code() == covio_platform::PlatformErrorCode::Unavailable => return,
            Err(error) => {
                self.local_message = Some(error.message().to_owned());
                return;
            }
        };
        if self.last_clipboard_text.as_deref() == Some(text.as_str()) {
            return;
        }
        self.last_clipboard_text = Some(text.clone());
        self.send_core_command(
            "clipboard.captureText",
            json!({"text": text, "sourceBundleId": "windows.clipboard"}),
        );
    }

    fn poll_screenshot_shelf(&mut self) {
        if Instant::now() < self.next_screenshot_poll {
            return;
        }
        self.next_screenshot_poll = Instant::now() + Duration::from_secs(3);
        let Some(directory) = self.screenshot_directory.as_ref() else {
            return;
        };
        let current = image_paths_in(directory);
        if !self.screenshot_scan_initialized {
            self.known_screenshots = current;
            self.screenshot_scan_initialized = true;
            return;
        }
        let new_paths: Vec<String> = current
            .difference(&self.known_screenshots)
            .map(|path| path.to_string_lossy().into_owned())
            .collect();
        if new_paths.is_empty() {
            return;
        }
        if self.model.pending_request().is_some() {
            return;
        }
        self.known_screenshots = current;
        self.send_core_command("shelf.addPaths", json!({"paths": new_paths}));
    }

    fn add_shelf_files(&mut self) {
        let request = FilePickerRequest::new("Add screenshots")
            .with_extensions(["png", "jpg", "jpeg", "heic", "heif", "webp", "bmp"])
            .multiple(true);
        match self.adapters.file_picker.pick_files(&request) {
            Ok(Some(paths)) if !paths.is_empty() => {
                let paths: Vec<String> = paths
                    .into_iter()
                    .map(|path| path.to_string_lossy().into_owned())
                    .collect();
                self.send_core_command("shelf.addPaths", json!({"paths": paths}));
            }
            Ok(_) => {}
            Err(error) => self.local_message = Some(error.message().to_owned()),
        }
    }

    fn remove_shelf_item(&mut self, path: &str) {
        let Some(snapshot) = self.model.snapshot().cloned() else {
            return;
        };
        let mut state = snapshot.shelf;
        state.items.retain(|item| item.path != path);
        self.send_core_command("shelf.save", json!({"state": state}));
    }

    fn clear_shelf(&mut self) {
        self.send_core_command("shelf.clear", json!({}));
    }

    fn capture_clipboard_now(&mut self) {
        match self.adapters.clipboard.read_text() {
            Ok(Some(text)) if !text.trim().is_empty() => {
                self.last_clipboard_text = Some(text.clone());
                self.send_core_command(
                    "clipboard.captureText",
                    json!({"text": text, "sourceBundleId": "windows.clipboard"}),
                );
            }
            Ok(_) => self.local_message = Some("Clipboard has no text.".to_owned()),
            Err(error) => self.local_message = Some(error.message().to_owned()),
        }
    }

    fn copy_clipboard_item(&mut self, item: &ClipItem) {
        let value = match item.kind {
            covio_core::clipboard::ClipKind::Image | covio_core::clipboard::ClipKind::Files => {
                item.file_path.clone()
            }
            _ => item.text.clone(),
        };
        if value.is_empty() {
            self.local_message = Some("Clipboard item has no content.".to_owned());
            return;
        }
        if let Err(error) = self.adapters.clipboard.write_text(&value) {
            self.local_message = Some(error.message().to_owned());
            return;
        }
        self.last_clipboard_text = Some(value);
        self.send_core_command("clipboard.markPaste", json!({"id": item.id}));
    }

    fn toggle_clipboard_pin(&mut self, item: &ClipItem) {
        self.send_core_command(
            "clipboard.setPinned",
            json!({"id": item.id, "pinned": !item.pinned}),
        );
    }

    fn remove_clipboard_item(&mut self, item: &ClipItem) {
        self.send_core_command("clipboard.remove", json!({"id": item.id}));
    }

    fn clear_clipboard(&mut self) {
        self.send_core_command("clipboard.clear", json!({}));
    }

    fn set_clipboard_paused(&mut self, paused: bool) {
        let Some(snapshot) = self.model.snapshot().cloned() else {
            return;
        };
        let mut state = snapshot.clipboard;
        state.paused = paused;
        self.send_core_command("clipboard.save", json!({"state": state}));
    }

    fn add_workspace_files(&mut self) {
        let Some(snapshot) = self.model.snapshot().cloned() else {
            return;
        };
        let request = FilePickerRequest::new("Add files to the workspace").multiple(true);
        match self.adapters.file_picker.pick_files(&request) {
            Ok(Some(paths)) if !paths.is_empty() => {
                let paths: Vec<String> = paths
                    .into_iter()
                    .map(|path| path.to_string_lossy().into_owned())
                    .collect();
                self.send_core_command(
                    "workspace.importFiles",
                    json!({
                        "state": snapshot.workspace,
                        "paths": paths,
                        "originDeviceId": windows_origin_device_id(),
                    }),
                );
            }
            Ok(_) => {}
            Err(error) => self.local_message = Some(error.message().to_owned()),
        }
    }

    fn save_workspace_text(&mut self) {
        let Some(snapshot) = self.model.snapshot().cloned() else {
            return;
        };
        let text = self.workspace_text.clone();
        if text.trim().is_empty() {
            self.local_message = Some("Enter text before saving.".to_owned());
            return;
        }
        self.send_core_command(
            "workspace.putText",
            json!({
                "state": snapshot.workspace,
                "text": text,
                "displayName": suggested_text_name(&self.workspace_text),
                "contentType": "text/plain",
                "originDeviceId": windows_origin_device_id(),
            }),
        );
        self.workspace_text.clear();
    }

    fn toggle_workspace_pin(&mut self, state: &WorkspaceState, entry_id: &str, pinned: bool) {
        self.send_core_command(
            "workspace.setPinned",
            json!({"state": state, "entryId": entry_id, "pinned": !pinned}),
        );
    }

    fn remove_workspace_entry(&mut self, state: &WorkspaceState, entry_id: &str) {
        self.send_core_command(
            "workspace.remove",
            json!({"state": state, "entryId": entry_id}),
        );
    }

    fn open_workspace_entry(&mut self, entry_id: &str) {
        let Some(path) = self.data_paths.workspace_content_path(entry_id) else {
            self.local_message = Some("Workspace content is unavailable.".to_owned());
            return;
        };
        if !path.is_file() {
            self.local_message = Some("Workspace content is unavailable.".to_owned());
            return;
        }
        self.open_path(&path);
    }

    fn clear_workspace(&mut self) {
        self.send_core_command("workspace.clear", json!({}));
    }

    fn open_path(&mut self, path: &Path) {
        match std::process::Command::new("explorer.exe").arg(path).spawn() {
            Ok(_) => {}
            Err(_) => self.local_message = Some("Cannot open the item.".to_owned()),
        }
    }

    fn open_releases(&mut self) {
        if webbrowser::open(RELEASES_URL).is_err() {
            self.local_message = Some("Cannot open the release page.".to_owned());
        }
    }

    fn notify(&self, title: &str, body: &str) {
        let _ = self
            .adapters
            .notifications
            .notify(&NotificationRequest::new(title, body));
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
        if context.input_mut(|input| input.consume_key(egui::Modifiers::CTRL, egui::Key::Num1)) {
            self.model.select_view(HostView::Home);
        }
        if context.input_mut(|input| input.consume_key(egui::Modifiers::CTRL, egui::Key::Num2)) {
            self.model.select_view(HostView::Shelf);
        }
        if context.input_mut(|input| input.consume_key(egui::Modifiers::CTRL, egui::Key::Num3)) {
            self.model.select_view(HostView::Clipboard);
        }
        if context.input_mut(|input| input.consume_key(egui::Modifiers::CTRL, egui::Key::Num4)) {
            self.model.select_view(HostView::Workspace);
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

    fn shelf_view(&mut self, ui: &mut egui::Ui) {
        ui.heading("Screenshot shelf");
        ui.label("Windows screenshots enter the shelf automatically. You can also add files.");
        ui.horizontal(|ui| {
            if ui.button("Add screenshots").clicked() {
                self.add_shelf_files();
            }
            if ui.button("Clear shelf").clicked() {
                self.clear_shelf();
            }
            if ui.button("Refresh").clicked() {
                self.refresh_snapshot();
            }
        });
        ui.add_space(12.0);
        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        if snapshot.shelf.items.is_empty() {
            ui.label("The shelf is empty.");
            return;
        }
        egui::ScrollArea::vertical().show(ui, |ui| {
            for item in snapshot.shelf.items {
                ui.group(|ui| {
                    ui.horizontal(|ui| {
                        ui.strong(display_name(&item.path));
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            if ui.button("Remove").clicked() {
                                self.remove_shelf_item(&item.path);
                            }
                            if ui.button("Open").clicked() {
                                self.open_path(Path::new(&item.path));
                            }
                        });
                    });
                    ui.small(&item.path);
                });
                ui.add_space(6.0);
            }
        });
    }

    fn clipboard_view(&mut self, ui: &mut egui::Ui) {
        ui.heading("Clipboard history");
        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        ui.label(if snapshot.clipboard.paused {
            "Recording is paused."
        } else {
            "Recording is active while the clipboard preference is enabled."
        });
        ui.horizontal(|ui| {
            if ui.button("Capture current text").clicked() {
                self.capture_clipboard_now();
            }
            let pause_label = if snapshot.clipboard.paused {
                "Resume recording"
            } else {
                "Pause recording"
            };
            if ui.button(pause_label).clicked() {
                self.set_clipboard_paused(!snapshot.clipboard.paused);
            }
            if ui.button("Clear history").clicked() {
                self.clear_clipboard();
            }
            if ui.button("Refresh").clicked() {
                self.refresh_snapshot();
            }
        });
        ui.add_space(12.0);
        if snapshot.clipboard.items.is_empty() {
            ui.label("Clipboard history is empty.");
            return;
        }
        egui::ScrollArea::vertical().show(ui, |ui| {
            for item in snapshot.clipboard.items {
                ui.group(|ui| {
                    ui.horizontal(|ui| {
                        ui.strong(format!("{:?}", item.kind));
                        ui.small(format!("{} bytes", item.byte_size));
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            if ui.button("Remove").clicked() {
                                self.remove_clipboard_item(&item);
                            }
                            if ui
                                .button(if item.pinned { "Unpin" } else { "Pin" })
                                .clicked()
                            {
                                self.toggle_clipboard_pin(&item);
                            }
                            if ui.button("Use").clicked() {
                                self.copy_clipboard_item(&item);
                            }
                        });
                    });
                    let preview = if item.text.is_empty() {
                        item.file_path.clone()
                    } else {
                        item.text.clone()
                    };
                    ui.label(single_line_preview(&preview, 160));
                });
                ui.add_space(6.0);
            }
        });
    }

    fn workspace_view(&mut self, ui: &mut egui::Ui) {
        ui.heading("Workspace");
        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        ui.horizontal(|ui| {
            if ui.button("Add files").clicked() {
                self.add_workspace_files();
            }
            if ui.button("Clear workspace").clicked() {
                self.clear_workspace();
            }
            if ui.button("Refresh").clicked() {
                self.refresh_snapshot();
            }
        });
        ui.horizontal(|ui| {
            ui.add(
                egui::TextEdit::singleline(&mut self.workspace_text)
                    .desired_width(420.0)
                    .hint_text("Save text to the workspace"),
            );
            if ui.button("Save text").clicked() {
                self.save_workspace_text();
            }
        });
        ui.add_space(12.0);
        if snapshot.workspace.entries.is_empty() {
            ui.label("The workspace is empty.");
            return;
        }
        let workspace = snapshot.workspace;
        egui::ScrollArea::vertical().show(ui, |ui| {
            for entry in workspace.entries.clone() {
                ui.group(|ui| {
                    ui.horizontal(|ui| {
                        ui.strong(&entry.display_name);
                        ui.small(format!("{:?} · {} bytes", entry.kind, entry.byte_size));
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            if ui.button("Remove").clicked() {
                                self.remove_workspace_entry(&workspace, &entry.entry_id);
                            }
                            if ui
                                .button(if entry.pinned { "Unpin" } else { "Pin" })
                                .clicked()
                            {
                                self.toggle_workspace_pin(
                                    &workspace,
                                    &entry.entry_id,
                                    entry.pinned,
                                );
                            }
                            if ui.button("Open").clicked() {
                                self.open_workspace_entry(&entry.entry_id);
                            }
                        });
                    });
                    ui.small(format!("{} · {:?}", entry.content_type, entry.availability));
                });
                ui.add_space(6.0);
            }
        });
    }

    fn settings_view(&mut self, ui: &mut egui::Ui) {
        ui.label("These settings are stored by the Rust core.");
        ui.label("Windows capability adapters are active in this process.");
        ui.add_space(12.0);

        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        let mut draft = self
            .draft_config
            .take()
            .unwrap_or_else(|| AppConfig::from_json_value(&snapshot.config));
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

        ui.add_space(12.0);
        ui.separator();
        ui.label("Updates");
        egui::Grid::new("windows-update-grid")
            .num_columns(2)
            .spacing([24.0, 8.0])
            .show(ui, |ui| {
                ui.label("Installed release");
                ui.monospace(CURRENT_VERSION);
                ui.end_row();
                ui.label("Check status");
                ui.label(if covio_core::should_check(&draft, now_epoch_seconds()) {
                    "Due"
                } else if draft.update_check_enabled {
                    "Not due"
                } else {
                    "Disabled"
                });
                ui.end_row();
            });
        if ui.button("Open releases").clicked() {
            self.open_releases();
        }

        ui.add_space(12.0);
        ui.separator();
        ui.label("Windows capabilities");
        ui.small(format!(
            "Credential Manager: {}",
            available_label(
                self.adapters
                    .capabilities
                    .status(covio_platform::CapabilityKind::SecureStorage)
                    .available
            )
        ));
        ui.small(format!(
            "Clipboard: {}",
            available_label(
                self.adapters
                    .capabilities
                    .status(covio_platform::CapabilityKind::Clipboard)
                    .available
            )
        ));
        ui.small(format!(
            "Screenshot directory: {}",
            if self.screenshot_directory.is_some() {
                "available"
            } else {
                "unavailable"
            }
        ));
        ui.small(format!(
            "Sleep and lid control: {}",
            if self
                .adapters
                .capabilities
                .status(covio_platform::CapabilityKind::Power)
                .available
            {
                "available"
            } else {
                "not available on Windows"
            }
        ));

        ui.add_space(16.0);
        let save = ui.button("Save").clicked();
        let config = draft.clone();
        self.draft_config = Some(draft);
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
        if let Some(message) = &self.local_message {
            ui.label(message);
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
        self.poll_clipboard_capture();
        self.poll_screenshot_shelf();
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
                    .selectable_label(self.model.view() == HostView::Shelf, "Shelf")
                    .clicked()
                {
                    self.model.select_view(HostView::Shelf);
                }
                if ui
                    .selectable_label(self.model.view() == HostView::Clipboard, "Clipboard")
                    .clicked()
                {
                    self.model.select_view(HostView::Clipboard);
                }
                if ui
                    .selectable_label(self.model.view() == HostView::Workspace, "Workspace")
                    .clicked()
                {
                    self.model.select_view(HostView::Workspace);
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
            match self.model.view() {
                HostView::Home | HostView::Settings => self.home_view(ui),
                HostView::Shelf => self.shelf_view(ui),
                HostView::Clipboard => self.clipboard_view(ui),
                HostView::Workspace => self.workspace_view(ui),
            }
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

fn view_from_arguments(arguments: &[String]) -> Option<HostView> {
    let value = arguments
        .iter()
        .position(|argument| argument == "--view")
        .and_then(|index| arguments.get(index + 1))
        .map(String::as_str)?;
    match value {
        "home" => Some(HostView::Home),
        "shelf" => Some(HostView::Shelf),
        "clipboard" => Some(HostView::Clipboard),
        "workspace" => Some(HostView::Workspace),
        "settings" => Some(HostView::Settings),
        _ => None,
    }
}

fn ui_scale_from_arguments(arguments: &[String]) -> Option<f32> {
    arguments
        .iter()
        .position(|argument| argument == "--ui-scale")
        .and_then(|index| arguments.get(index + 1))
        .and_then(|value| value.parse::<f32>().ok())
        .filter(|value| (0.75..=3.0).contains(value))
}

fn window_position_from_arguments(arguments: &[String]) -> Option<[f32; 2]> {
    let value = arguments
        .iter()
        .position(|argument| argument == "--window-position")
        .and_then(|index| arguments.get(index + 1))?;
    let (x, y) = value.split_once(',')?;
    let x = x.trim().parse::<f32>().ok()?;
    let y = y.trim().parse::<f32>().ok()?;
    (x.is_finite() && y.is_finite()).then_some([x, y])
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

fn image_paths_in(directory: &Path) -> BTreeSet<PathBuf> {
    let Ok(entries) = std::fs::read_dir(directory) else {
        return BTreeSet::new();
    };
    entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.is_file()
                && path
                    .extension()
                    .and_then(|extension| extension.to_str())
                    .is_some_and(|extension| {
                        matches!(
                            extension.to_ascii_lowercase().as_str(),
                            "png" | "jpg" | "jpeg" | "heic" | "heif" | "webp" | "bmp"
                        )
                    })
        })
        .collect()
}

fn windows_origin_device_id() -> String {
    std::env::var("COMPUTERNAME").map_or_else(
        |_| "windows-local".to_owned(),
        |name| format!("windows:{}", name.trim()),
    )
}

fn display_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or(path)
        .to_owned()
}

fn single_line_preview(value: &str, limit: usize) -> String {
    let mut preview = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if preview.chars().count() > limit {
        preview = preview.chars().take(limit).collect::<String>() + "...";
    }
    preview
}

fn available_label(available: bool) -> &'static str {
    if available {
        "available"
    } else {
        "unavailable"
    }
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

    #[test]
    fn display_smoke_arguments_are_bounded() {
        let arguments = vec![
            "covio-windows.exe".to_owned(),
            "--ui-scale".to_owned(),
            "1.5".to_owned(),
            "--window-position".to_owned(),
            "1920,120".to_owned(),
        ];
        assert_eq!(ui_scale_from_arguments(&arguments), Some(1.5));
        assert_eq!(
            window_position_from_arguments(&arguments),
            Some([1920.0, 120.0])
        );
        assert_eq!(
            ui_scale_from_arguments(&[
                "covio-windows.exe".to_owned(),
                "--ui-scale".to_owned(),
                "9".to_owned(),
            ]),
            None
        );
    }

    #[test]
    fn screenshot_view_argument_selects_product_surfaces() {
        let arguments = vec![
            "covio-windows.exe".to_owned(),
            "--view".to_owned(),
            "workspace".to_owned(),
        ];
        assert_eq!(view_from_arguments(&arguments), Some(HostView::Workspace));
    }
}
