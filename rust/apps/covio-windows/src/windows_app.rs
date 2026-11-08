//! Windows-only egui composition root.

use crate::top_edge::{TopEdgeMonitor, WindowsUiSettings};
use crate::visuals::{
    BENTO_CARD_PADDING, BENTO_COLUMNS, BENTO_GAP, BENTO_MAX_ROWS, BENTO_ROW_HEIGHT, CovioTheme,
    HUB_ACTION_WIDTH, HUB_HOME_WIDTH, HUB_ITEM_GAP, HUB_NAV_HEIGHT, HUB_PANEL_PADDING,
    HUB_PANEL_WIDTH, HUB_SEARCH_WIDTH, HUB_TAB_BAR_HEIGHT, HUB_TAB_GAP, HUB_TAB_WIDTH,
    PAGE_MAX_WIDTH, SETTINGS_CONTENT_WIDTH, SETTINGS_ROW_HEIGHT, SETTINGS_TOOLBAR_HEIGHT,
    WIDGET_TINT_AMBER, WIDGET_TINT_APRICOT, WIDGET_TINT_MINT, WIDGET_TINT_ROSE, WIDGET_TINT_SKY,
    WIDGET_TINT_SLATE,
};
use covio_core::AppConfig;
use covio_core::clipboard::ClipItem;
use covio_core::workspace::{WorkspaceState, suggested_text_name};
use covio_platform::{
    Clipboard, FilePicker, FilePickerRequest, FileStore, NotificationRequest, Notifier,
    ScreenshotDirectory, StartupRegistration, StartupSpec, WindowsAppDataDirectory,
    WindowsPlatformAdapters,
};
use covio_windows::{
    CloseDisposition, CoreRuntime, HostModel, HostSnapshot, HostStatus, HostView, ThemePreference,
    WindowsDataPaths, now_epoch_seconds,
};
use eframe::egui;
use eframe::egui_wgpu::{WgpuConfiguration, WgpuSetup, WgpuSetupCreateNew};
use eframe::wgpu;
use global_hotkey::hotkey::{Code, HotKey, Modifiers as GlobalHotKeyModifiers};
use global_hotkey::{GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use serde_json::json;
use single_instance::SingleInstance;
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tray_icon::menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem};
use tray_icon::{TrayIcon, TrayIconBuilder, TrayIconEvent};
use windows_sys::Win32::Foundation::SYSTEMTIME;
use windows_sys::Win32::System::SystemInformation::GetLocalTime;

const INSTANCE_NAME: &str = "Local\\com.wyz.covio.windows";
const SCREENSHOT_INSTANCE_NAME: &str = "Local\\com.wyz.covio.windows.screenshot";
const RELEASES_URL: &str = "https://github.com/wyz541/kmp-Covio/releases";
const HUB_TOGGLE_SHORTCUT: &str = "Ctrl+Alt+T";
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum SettingsSection {
    Overview,
    Appearance,
    Triggers,
    Capabilities,
    Updates,
}

impl SettingsSection {
    fn summary(self) -> &'static str {
        match self {
            Self::Overview => "General behavior and startup",
            Self::Appearance => "Theme and motion",
            Self::Triggers => "Workbench entry points",
            Self::Capabilities => "Windows adapter status",
            Self::Updates => "Release and update status",
        }
    }

    fn search_terms(self) -> &'static str {
        match self {
            Self::Overview => "covio enabled launch login clipboard notifications updates status",
            Self::Appearance => "theme light dark system motion",
            Self::Triggers => "workbench top edge shortcut tray pointer 180",
            Self::Capabilities => "credential manager clipboard screenshot sleep adapter",
            Self::Updates => "release update check version",
        }
    }
}

const SETTINGS_SECTIONS: [(SettingsSection, &str); 5] = [
    (SettingsSection::Overview, "Overview"),
    (SettingsSection::Appearance, "Appearance"),
    (SettingsSection::Triggers, "Triggers"),
    (SettingsSection::Capabilities, "Capabilities"),
    (SettingsSection::Updates, "Updates"),
];

const WORKBENCH_TABS: [(HostView, &str); 3] = [
    (HostView::Shelf, "Shelf"),
    (HostView::Clipboard, "Clipboard"),
    (HostView::Workspace, "Workspace"),
];
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

    let screenshot_path = screenshot_path_from_arguments(&arguments);
    let instance_name = instance_name_for_arguments(&arguments);
    let instance = SingleInstance::new(instance_name).map_err(|error| error.to_string())?;
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
    let initial_settings_section = settings_section_from_arguments(&arguments);
    let ui_scale = ui_scale_from_arguments(&arguments);
    let window_position = window_position_from_arguments(&arguments);
    let auto_exit_frames = arguments
        .iter()
        .any(|argument| argument == "--window-smoke")
        .then_some(8_u32);
    let settings_initial = matches!(initial_view, Some(HostView::Settings));
    let inner_size = window_inner_size(initial_view.unwrap_or(HostView::Home));
    let min_inner_size = if settings_initial {
        [720.0, 560.0]
    } else {
        [720.0, 640.0]
    };
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_title("Covio")
            .with_inner_size(inner_size)
            .with_min_inner_size(min_inner_size)
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
                    settings_section: initial_settings_section,
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
    settings_section: Option<SettingsSection>,
}

struct CovioWindowsApp {
    core: CoreRuntime,
    data_paths: WindowsDataPaths,
    adapters: WindowsPlatformAdapters,
    model: HostModel,
    tray: Option<TrayController>,
    tray_error: Option<String>,
    global_hotkey: Option<HubHotKey>,
    global_hotkey_error: Option<String>,
    top_edge_monitor: TopEdgeMonitor,
    top_edge_runtime_error: Option<String>,
    pending_background_hide: bool,
    last_view: HostView,
    workbench_search: String,
    settings_search: String,
    pending_config_save: Option<AppConfig>,
    ui_settings_path: PathBuf,
    ui_settings_error: Option<String>,
    draft_config: Option<AppConfig>,
    settings_section: SettingsSection,
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
        let (global_hotkey, global_hotkey_error) = match HubHotKey::register() {
            Ok(hotkey) => (Some(hotkey), None),
            Err(error) => (None, Some(error)),
        };
        let adapters = WindowsPlatformAdapters::default();
        let ui_settings_path = data_paths.ui_settings_file();
        let (ui_settings, ui_settings_error) =
            load_windows_ui_settings(&adapters, &ui_settings_path);
        let window_handle =
            creation_context
                .window_handle()
                .ok()
                .and_then(|handle| match handle.as_raw() {
                    RawWindowHandle::Win32(handle) => Some(handle.hwnd.get()),
                    _ => None,
                });
        let top_edge_monitor = TopEdgeMonitor::new(
            ui_settings.top_edge_trigger_enabled,
            model.is_visible(),
            creation_context.egui_ctx.clone(),
            window_handle,
        );
        let top_edge_runtime_error = top_edge_monitor.startup_error().map(str::to_owned);
        let screenshot_directory = adapters.screenshots.directory().ok();
        let last_view = model.view();
        let mut app = Self {
            core: CoreRuntime::new(core),
            data_paths,
            adapters,
            model,
            tray,
            tray_error,
            global_hotkey,
            global_hotkey_error,
            top_edge_monitor,
            top_edge_runtime_error,
            pending_background_hide: options.start_hidden,
            last_view,
            workbench_search: String::new(),
            settings_search: String::new(),
            pending_config_save: None,
            ui_settings_path,
            ui_settings_error,
            draft_config: None,
            settings_section: options
                .settings_section
                .unwrap_or(SettingsSection::Overview),
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

    fn flush_pending_config_save(&mut self) {
        if self.model.pending_request().is_some() {
            return;
        }
        if let Some(config) = self.pending_config_save.take() {
            self.save_config(config);
        }
    }

    fn poll_core(&mut self) {
        while let Some(response) = self.core.try_response() {
            let command = response.command.clone();
            let succeeded = response.ok;
            let result = response.result.clone();
            if self.model.apply_response(response) {
                if command == "config.save" && self.pending_config_save.is_none() {
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
                TrayAction::OpenScreenshots => {
                    self.model.show_shelf();
                    show_window(context);
                }
                TrayAction::OpenSettings => {
                    self.model.show_settings();
                    show_window(context);
                }
                TrayAction::ToggleWindow => {
                    self.model.toggle_window();
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

    fn poll_global_hotkey(&mut self, context: &egui::Context) {
        let target_id = self.global_hotkey.as_ref().map(HubHotKey::id);
        while let Ok(event) = GlobalHotKeyEvent::receiver().try_recv() {
            if !is_hub_toggle_event(event, target_id) {
                continue;
            }
            self.model.toggle_window();
            if self.model.is_visible() {
                show_window(context);
            } else {
                hide_window(context);
            }
            context.request_repaint();
        }
    }

    fn poll_top_edge_trigger(&mut self, context: &egui::Context) {
        let triggered = self.top_edge_monitor.take_triggered();
        if !triggered || !self.top_edge_monitor.is_enabled() || self.model.is_visible() {
            return;
        }
        self.model.show();
        self.top_edge_monitor.set_window_visible(true);
        show_window(context);
    }

    fn set_top_edge_enabled(&mut self, enabled: bool) {
        self.top_edge_monitor.set_enabled(enabled);
        self.top_edge_monitor
            .set_window_visible(self.model.is_visible());
        let settings = WindowsUiSettings {
            top_edge_trigger_enabled: enabled,
        };
        match serde_json::to_vec_pretty(&settings)
            .map_err(|error| error.to_string())
            .and_then(|bytes| {
                self.adapters
                    .filesystem
                    .write_atomic(&self.ui_settings_path, &bytes)
                    .map_err(|error| error.message().to_owned())
            }) {
            Ok(()) => self.ui_settings_error = None,
            Err(error) => self.ui_settings_error = Some(error),
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
            if self.model.view() == HostView::Settings {
                self.settings_search.clear();
                self.model.show_home();
            } else {
                self.model.hide();
                hide_window(context);
            }
        }
    }

    fn sync_window_size(&mut self, context: &egui::Context) {
        let view = self.model.view();
        if view == self.last_view {
            return;
        }
        let [width, height] = window_inner_size(view);
        context.send_viewport_cmd(egui::ViewportCommand::InnerSize(egui::Vec2::new(
            width, height,
        )));
        self.last_view = view;
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

    fn covio_theme(&self) -> CovioTheme {
        let dark = match self.model.theme() {
            ThemePreference::System => dark_light::detect() == dark_light::Mode::Dark,
            ThemePreference::Light => false,
            ThemePreference::Dark => true,
        };
        CovioTheme::from_dark(dark)
    }

    fn apply_visuals(&self, context: &egui::Context) {
        self.covio_theme().apply(context);
        context.style_mut(|style| {
            style.animation_time = if self.model.reduced_motion() {
                0.0
            } else {
                0.16
            };
        });
    }

    fn workbench_view(&mut self, ui: &mut egui::Ui) {
        let theme = self.covio_theme();
        let available = ui.available_size();
        let panel_width = available.x.min(HUB_PANEL_WIDTH);
        ui.with_layout(egui::Layout::top_down(egui::Align::Center), |ui| {
            theme.workbench_plate_frame().show(ui, |ui| {
                ui.set_min_size(egui::Vec2::new(panel_width, available.y));
                self.workbench_top_bar(ui, theme, panel_width);
                egui::ScrollArea::vertical()
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        ui.add_space(11.0 + HUB_PANEL_PADDING);
                        with_page_width(ui, |ui| {
                            self.render_status(ui);
                            if let Some(message) = &self.local_message {
                                theme.muted_frame().show(ui, |ui| {
                                    ui.label(message);
                                });
                                ui.add_space(8.0);
                            }
                            match self.model.view() {
                                HostView::Home => self.home_view(ui),
                                HostView::Shelf => self.shelf_view(ui),
                                HostView::Clipboard => self.clipboard_view(ui),
                                HostView::Workspace => self.workspace_view(ui),
                                HostView::Settings => {}
                            }
                        });
                        ui.add_space(HUB_PANEL_PADDING);
                    });
            });
        });
    }

    fn workbench_top_bar(&mut self, ui: &mut egui::Ui, theme: CovioTheme, panel_width: f32) {
        ui.allocate_ui_with_layout(
            egui::Vec2::new(panel_width, HUB_TAB_BAR_HEIGHT),
            egui::Layout::left_to_right(egui::Align::Center),
            |ui| {
                ui.add_space(HUB_PANEL_PADDING);
                workbench_search_field(ui, theme, &mut self.workbench_search);
                ui.add_space(HUB_ITEM_GAP);
                if workbench_nav_button(
                    ui,
                    theme,
                    "Home",
                    self.model.view() == HostView::Home,
                    HUB_HOME_WIDTH,
                )
                .clicked()
                {
                    self.model.select_view(HostView::Home);
                }
                ui.add_space(HUB_ITEM_GAP);
                for (view, label) in WORKBENCH_TABS {
                    if workbench_nav_button(
                        ui,
                        theme,
                        label,
                        self.model.view() == view,
                        HUB_TAB_WIDTH,
                    )
                    .clicked()
                    {
                        self.model.select_view(view);
                    }
                    ui.add_space(HUB_TAB_GAP);
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if workbench_action_button(ui, theme, "Settings", HUB_ACTION_WIDTH).clicked() {
                        self.model.show_settings();
                    }
                    ui.add_space(HUB_PANEL_PADDING);
                });
            },
        );
    }
    fn home_view(&mut self, ui: &mut egui::Ui) {
        let theme = self.covio_theme();
        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };

        let cards = home_bento_cards(&snapshot);
        let query = self.workbench_search.trim().to_lowercase();
        if query.is_empty() {
            bento_grid(ui, theme, &cards);
        } else {
            let matches: Vec<&BentoCard> = cards
                .iter()
                .filter(|card| {
                    card.title.to_lowercase().contains(&query)
                        || card.detail.to_lowercase().contains(&query)
                })
                .collect();
            if matches.is_empty() {
                empty_state(
                    ui,
                    theme,
                    "No results",
                    "No Workbench card matches the search.",
                    |_ui| {},
                );
            } else {
                for card in matches {
                    let width = ui.available_width();
                    let (rect, _) = ui.allocate_exact_size(
                        egui::Vec2::new(width, BENTO_ROW_HEIGHT),
                        egui::Sense::hover(),
                    );
                    draw_bento_card(ui, theme, rect, card);
                    ui.add_space(BENTO_GAP);
                }
            }
        }

        if let Some(error) = &self.tray_error {
            ui.add_space(BENTO_GAP);
            theme.muted_frame().show(ui, |ui| {
                ui.colored_label(theme.warning, error);
            });
        }
    }
    fn shelf_view(&mut self, ui: &mut egui::Ui) {
        let theme = self.covio_theme();
        ui.heading("Screenshot shelf");
        ui.label("Screenshots enter the shelf automatically. You can also add files.");
        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        ui.add_space(12.0);
        theme.toolbar_frame().show(ui, |ui| {
            ui.horizontal_wrapped(|ui| {
                if ui.add(theme.primary_button("Add screenshots")).clicked() {
                    self.add_shelf_files();
                }
                if ui
                    .add_enabled(
                        !snapshot.shelf.items.is_empty(),
                        theme.destructive_button("Clear shelf"),
                    )
                    .clicked()
                {
                    self.clear_shelf();
                }
                if ui.add(theme.secondary_button("Refresh")).clicked() {
                    self.refresh_snapshot();
                }
            });
        });
        ui.add_space(16.0);

        if snapshot.shelf.items.is_empty() {
            empty_state(
                ui,
                theme,
                "No screenshots yet",
                "Add screenshots or save them in the Windows Screenshots folder.",
                |ui| {
                    if ui.add(theme.primary_button("Add screenshots")).clicked() {
                        self.add_shelf_files();
                    }
                },
            );
            return;
        }

        ui.spacing_mut().item_spacing = egui::Vec2::new(12.0, 12.0);
        ui.horizontal_wrapped(|ui| {
            for item in snapshot.shelf.items {
                let extension = extension_label(&item.path);
                let card_size = egui::Vec2::new(192.0, 202.0);
                ui.allocate_ui_with_layout(
                    card_size,
                    egui::Layout::top_down(egui::Align::Min),
                    |ui| {
                        theme.card_frame().show(ui, |ui| {
                            ui.set_min_size(egui::Vec2::new(160.0, 170.0));
                            file_preview(ui, theme, &extension, WIDGET_TINT_SLATE);
                            ui.add_space(8.0);
                            ui.label(
                                egui::RichText::new(display_name(&item.path))
                                    .strong()
                                    .color(theme.text_primary),
                            )
                            .on_hover_text(&item.path);
                            ui.add_space(8.0);
                            ui.horizontal(|ui| {
                                if ui.add(theme.secondary_button("Open")).clicked() {
                                    self.open_path(Path::new(&item.path));
                                }
                                if ui.add(theme.destructive_button("Remove")).clicked() {
                                    self.remove_shelf_item(&item.path);
                                }
                            });
                        });
                    },
                );
            }
        });
    }

    fn clipboard_view(&mut self, ui: &mut egui::Ui) {
        let theme = self.covio_theme();
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
        ui.add_space(12.0);
        theme.toolbar_frame().show(ui, |ui| {
            ui.horizontal_wrapped(|ui| {
                if ui
                    .add(theme.secondary_button("Capture current text"))
                    .clicked()
                {
                    self.capture_clipboard_now();
                }
                let pause_label = if snapshot.clipboard.paused {
                    "Resume recording"
                } else {
                    "Pause recording"
                };
                if ui.add(theme.secondary_button(pause_label)).clicked() {
                    self.set_clipboard_paused(!snapshot.clipboard.paused);
                }
                if ui
                    .add_enabled(
                        !snapshot.clipboard.items.is_empty(),
                        theme.destructive_button("Clear history"),
                    )
                    .clicked()
                {
                    self.clear_clipboard();
                }
                if ui.add(theme.secondary_button("Refresh")).clicked() {
                    self.refresh_snapshot();
                }
            });
        });
        ui.add_space(16.0);
        if snapshot.clipboard.items.is_empty() {
            empty_state(
                ui,
                theme,
                "Clipboard history is empty",
                "Capture the current clipboard text to create the first item.",
                |ui| {
                    if ui
                        .add(theme.primary_button("Capture current text"))
                        .clicked()
                    {
                        self.capture_clipboard_now();
                    }
                },
            );
            return;
        }
        for item in snapshot.clipboard.items {
            content_card(ui, theme, |ui| {
                ui.horizontal(|ui| {
                    type_badge(ui, theme, clipboard_kind_label(item.kind));
                    ui.small(format!("{} bytes", item.byte_size));
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.add(theme.destructive_button("Remove")).clicked() {
                            self.remove_clipboard_item(&item);
                        }
                        if ui
                            .add(theme.secondary_button(if item.pinned { "Unpin" } else { "Pin" }))
                            .clicked()
                        {
                            self.toggle_clipboard_pin(&item);
                        }
                        if ui.add(theme.primary_button("Use")).clicked() {
                            self.copy_clipboard_item(&item);
                        }
                    });
                });
                ui.add_space(8.0);
                let preview = if item.text.is_empty() {
                    item.file_path.clone()
                } else {
                    item.text.clone()
                };
                ui.label(single_line_preview(&preview, 180));
            });
            ui.add_space(10.0);
        }
    }

    fn workspace_view(&mut self, ui: &mut egui::Ui) {
        let theme = self.covio_theme();
        ui.heading("Workspace");
        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        ui.add_space(12.0);
        theme.toolbar_frame().show(ui, |ui| {
            ui.horizontal_wrapped(|ui| {
                if ui.add(theme.primary_button("Add files")).clicked() {
                    self.add_workspace_files();
                }
                if ui
                    .add_enabled(
                        !snapshot.workspace.entries.is_empty(),
                        theme.destructive_button("Clear workspace"),
                    )
                    .clicked()
                {
                    self.clear_workspace();
                }
                if ui.add(theme.secondary_button("Refresh")).clicked() {
                    self.refresh_snapshot();
                }
            });
            ui.add_space(8.0);
            ui.horizontal(|ui| {
                ui.add(
                    egui::TextEdit::singleline(&mut self.workspace_text)
                        .desired_width(420.0)
                        .hint_text("Save text to the workspace"),
                );
                if ui.add(theme.primary_button("Save text")).clicked() {
                    self.save_workspace_text();
                }
            });
        });
        ui.add_space(16.0);
        if snapshot.workspace.entries.is_empty() {
            empty_state(
                ui,
                theme,
                "The workspace is empty",
                "Add files or save text to start a local workspace.",
                |ui| {
                    if ui.add(theme.primary_button("Add files")).clicked() {
                        self.add_workspace_files();
                    }
                },
            );
            return;
        }
        let workspace = snapshot.workspace;
        for entry in workspace.entries.clone() {
            content_card(ui, theme, |ui| {
                ui.horizontal(|ui| {
                    ui.strong(&entry.display_name);
                    ui.small(format!("{:?} · {} bytes", entry.kind, entry.byte_size));
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.add(theme.destructive_button("Remove")).clicked() {
                            self.remove_workspace_entry(&workspace, &entry.entry_id);
                        }
                        if ui
                            .add(theme.secondary_button(if entry.pinned { "Unpin" } else { "Pin" }))
                            .clicked()
                        {
                            self.toggle_workspace_pin(&workspace, &entry.entry_id, entry.pinned);
                        }
                        if ui.add(theme.primary_button("Open")).clicked() {
                            self.open_workspace_entry(&entry.entry_id);
                        }
                    });
                });
                ui.add_space(6.0);
                ui.small(format!("{} · {:?}", entry.content_type, entry.availability));
            });
            ui.add_space(10.0);
        }
    }

    fn settings_view(&mut self, ui: &mut egui::Ui) {
        let theme = self.covio_theme();
        let Some(snapshot) = self.model.snapshot().cloned() else {
            ui.spinner();
            return;
        };
        let mut draft = self
            .draft_config
            .take()
            .unwrap_or_else(|| AppConfig::from_json_value(&snapshot.config));
        let mut config_changed = false;

        ui.allocate_ui_with_layout(
            egui::Vec2::new(ui.available_width(), SETTINGS_TOOLBAR_HEIGHT),
            egui::Layout::left_to_right(egui::Align::Center),
            |ui| {
                ui.add_space(16.0);
                if settings_back_button(ui, theme).clicked() {
                    self.settings_search.clear();
                    self.model.show_home();
                }
                ui.add_space(8.0);
                for (section, label) in SETTINGS_SECTIONS {
                    if settings_tab_button(
                        ui,
                        theme,
                        section,
                        label,
                        self.settings_section == section,
                    )
                    .clicked()
                    {
                        self.settings_section = section;
                        self.settings_search.clear();
                    }
                    ui.add_space(4.0);
                }
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    ui.add_space(16.0);
                    settings_search_field(ui, theme, &mut self.settings_search);
                });
            },
        );
        ui.separator();

        egui::ScrollArea::vertical()
            .auto_shrink([false, false])
            .show(ui, |ui| {
                ui.add_space(32.0);
                with_settings_content_width(ui, |ui| {
                    if !self.settings_search.trim().is_empty() {
                        settings_group_title(ui, theme, "Search Results");
                        let query = self.settings_search.trim().to_lowercase();
                        let matches: Vec<(SettingsSection, &str)> = SETTINGS_SECTIONS
                            .iter()
                            .copied()
                            .filter(|(section, label)| {
                                settings_section_matches(*section, label, &query)
                            })
                            .collect();
                        if matches.is_empty() {
                            settings_group(ui, theme, |ui| {
                                settings_label_row(ui, theme, "No settings match this search.");
                            });
                        } else {
                            settings_group(ui, theme, |ui| {
                                for (index, (section, label)) in matches.iter().enumerate() {
                                    if index > 0 {
                                        settings_divider(ui, theme);
                                    }
                                    if settings_search_result_row(ui, theme, *section, label).clicked()
                                    {
                                        self.settings_section = *section;
                                        self.settings_search.clear();
                                    }
                                }
                            });
                        }
                    } else {
                        match self.settings_section {
                            SettingsSection::Overview => {
                                settings_group_title(ui, theme, "Behavior");
                                settings_group(ui, theme, |ui| {
                                    config_changed |= settings_toggle_row(
                                        ui,
                                        theme,
                                        "Covio enabled",
                                        "covio-enabled",
                                        &mut draft.enabled,
                                    );
                                    settings_divider(ui, theme);
                                    config_changed |= settings_toggle_row(
                                        ui,
                                        theme,
                                        "Launch at login",
                                        "launch-at-login",
                                        &mut draft.launch_at_login,
                                    );
                                    settings_divider(ui, theme);
                                    config_changed |= settings_toggle_row(
                                        ui,
                                        theme,
                                        "Capture clipboard history",
                                        "capture-clipboard",
                                        &mut draft.clipboard_enabled,
                                    );
                                    settings_divider(ui, theme);
                                    config_changed |= settings_toggle_row(
                                        ui,
                                        theme,
                                        "Show notifications",
                                        "show-notifications",
                                        &mut draft.notifications_enabled,
                                    );
                                    settings_divider(ui, theme);
                                    config_changed |= settings_toggle_row(
                                        ui,
                                        theme,
                                        "Check for updates",
                                        "check-for-updates",
                                        &mut draft.update_check_enabled,
                                    );
                                });

                                settings_group_title(ui, theme, "Status");
                                settings_group(ui, theme, |ui| {
                                    settings_value_row(
                                        ui,
                                        theme,
                                        "Core",
                                        status_text(self.model.status()),
                                    );
                                    settings_divider(ui, theme);
                                    settings_value_row(
                                        ui,
                                        theme,
                                        "Screenshots",
                                        &count_label(
                                            snapshot.shelf_item_count,
                                            "item",
                                            "items",
                                        ),
                                    );
                                    settings_divider(ui, theme);
                                    settings_value_row(
                                        ui,
                                        theme,
                                        "Clipboard",
                                        &count_label(
                                            snapshot.clipboard_item_count,
                                            "item",
                                            "items",
                                        ),
                                    );
                                    settings_divider(ui, theme);
                                    settings_value_row(
                                        ui,
                                        theme,
                                        "Workspace",
                                        &count_label(
                                            snapshot.workspace_entry_count,
                                            "entry",
                                            "entries",
                                        ),
                                    );
                                });
                            }
                            SettingsSection::Appearance => {
                                settings_group_title(ui, theme, "Appearance");
                                settings_group(ui, theme, |ui| {
                                    if let Some(theme_preference) =
                                        settings_theme_row(ui, theme, self.model.theme())
                                    {
                                        self.model.set_theme(theme_preference);
                                    }
                                    settings_divider(ui, theme);
                                    let mut reduced_motion = self.model.reduced_motion();
                                    if settings_toggle_row(
                                        ui,
                                        theme,
                                        "Reduce motion",
                                        "reduce-motion",
                                        &mut reduced_motion,
                                    ) {
                                        self.model.set_reduced_motion(reduced_motion);
                                    }
                                });
                            }
                            SettingsSection::Triggers => {
                                settings_group_title(ui, theme, "Workbench");
                                settings_group(ui, theme, |ui| {
                                    let mut top_edge_enabled = self.top_edge_monitor.is_enabled();
                                    if settings_toggle_row(
                                        ui,
                                        theme,
                                        "Show Workbench at the top edge",
                                        "top-edge-trigger",
                                        &mut top_edge_enabled,
                                    ) {
                                        self.set_top_edge_enabled(top_edge_enabled);
                                    }
                                    settings_divider(ui, theme);
                                    settings_description_row(
                                        ui,
                                        theme,
                                        "Hold the pointer at the top of any display for 180 ms.",
                                    );
                                    if let Some(error) = &self.ui_settings_error {
                                        settings_warning_row(
                                            ui,
                                            theme,
                                            &format!(
                                                "Cannot save the Windows UI setting: {error}"
                                            ),
                                        );
                                    }
                                    if let Some(error) = &self.top_edge_runtime_error {
                                        settings_warning_row(
                                            ui,
                                            theme,
                                            &format!("Top-edge trigger is unavailable: {error}"),
                                        );
                                    }
                                });

                                settings_group_title(ui, theme, "Shortcut");
                                settings_group(ui, theme, |ui| {
                                    settings_status_row(
                                        ui,
                                        theme,
                                        "Global shortcut",
                                        HUB_TOGGLE_SHORTCUT,
                                        if self.global_hotkey_error.is_some() {
                                            theme.warning
                                        } else {
                                            theme.success
                                        },
                                    );
                                    if let Some(error) = &self.global_hotkey_error {
                                        settings_warning_row(ui, theme, error);
                                    }
                                });

                                settings_group_title(ui, theme, "Tray");
                                settings_group(ui, theme, |ui| {
                                    settings_description_row(
                                        ui,
                                        theme,
                                        "Left click toggles the window. Right click opens commands.",
                                    );
                                    settings_divider(ui, theme);
                                    settings_description_row(
                                        ui,
                                        theme,
                                        "The macOS two-finger gesture is unavailable to egui.",
                                    );
                                });
                            }
                            SettingsSection::Capabilities => {
                                settings_group_title(ui, theme, "Windows capabilities");
                                settings_group(ui, theme, |ui| {
                                    settings_capability_row(
                                        ui,
                                        theme,
                                        "Credential Manager",
                                        self.adapters
                                            .capabilities
                                            .status(
                                                covio_platform::CapabilityKind::SecureStorage,
                                            )
                                            .available,
                                    );
                                    settings_divider(ui, theme);
                                    settings_capability_row(
                                        ui,
                                        theme,
                                        "Clipboard",
                                        self.adapters
                                            .capabilities
                                            .status(covio_platform::CapabilityKind::Clipboard)
                                            .available,
                                    );
                                    settings_divider(ui, theme);
                                    settings_capability_row(
                                        ui,
                                        theme,
                                        "Screenshot directory",
                                        self.screenshot_directory.is_some(),
                                    );
                                    settings_divider(ui, theme);
                                    settings_capability_row(
                                        ui,
                                        theme,
                                        "Sleep and lid control",
                                        self.adapters
                                            .capabilities
                                            .status(covio_platform::CapabilityKind::Power)
                                            .available,
                                    );
                                });
                            }
                            SettingsSection::Updates => {
                                settings_group_title(ui, theme, "Updates");
                                settings_group(ui, theme, |ui| {
                                    config_changed |= settings_toggle_row(
                                        ui,
                                        theme,
                                        "Automatically check for updates",
                                        "automatic-update-check",
                                        &mut draft.update_check_enabled,
                                    );
                                    settings_divider(ui, theme);
                                    settings_value_row(ui, theme, "Installed release", CURRENT_VERSION);
                                    settings_divider(ui, theme);
                                    settings_value_row(
                                        ui,
                                        theme,
                                        "Check status",
                                        if covio_core::should_check(&draft, now_epoch_seconds()) {
                                            "Due"
                                        } else if draft.update_check_enabled {
                                            "Not due"
                                        } else {
                                            "Disabled"
                                        },
                                    );
                                });
                                settings_group_title(ui, theme, "Release");
                                settings_group(ui, theme, |ui| {
                                    settings_action_row(ui, |ui| {
                                        if ui.add(theme.secondary_button("Open releases")).clicked()
                                        {
                                            self.open_releases();
                                        }
                                    });
                                });
                            }
                        }
                    }

                    if self.tray.is_none() {
                        ui.add_space(20.0);
                        settings_group(ui, theme, |ui| {
                            settings_warning_row(
                                ui,
                                theme,
                                self.tray_error
                                    .as_deref()
                                    .unwrap_or("Windows tray is unavailable."),
                            );
                        });
                    }
                });
                ui.add_space(40.0);
            });

        if config_changed {
            self.draft_config = Some(draft.clone());
            self.pending_config_save = Some(draft);
        } else {
            self.draft_config = Some(draft);
        }
    }
    fn render_status(&self, ui: &mut egui::Ui) {
        let theme = self.covio_theme();
        match self.model.status() {
            HostStatus::Idle | HostStatus::Ready => {}
            HostStatus::Loading => {
                ui.horizontal(|ui| {
                    ui.spinner();
                    ui.label("Loading core state...");
                });
                ui.add_space(8.0);
            }
            HostStatus::Error(message) => {
                theme.muted_frame().show(ui, |ui| {
                    ui.colored_label(theme.error, message);
                });
                ui.add_space(8.0);
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
        if self.pending_background_hide {
            self.pending_background_hide = false;
            self.top_edge_monitor.hide_window();
            context.send_viewport_cmd(egui::ViewportCommand::Visible(false));
        }
        self.poll_tray(context);
        self.poll_top_edge_trigger(context);
        self.poll_global_hotkey(context);
        self.poll_core();
        self.flush_pending_config_save();
        self.poll_clipboard_capture();
        self.poll_screenshot_shelf();
        self.handle_keyboard(context);
        self.handle_close(context);
        self.sync_window_size(context);
        self.top_edge_monitor
            .set_window_visible(self.model.is_visible());
        self.apply_visuals(context);

        if !self.model.is_visible() {
            return;
        }

        let theme = self.covio_theme();
        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(theme.canvas))
            .show(context, |ui| {
                if self.model.view() == HostView::Settings {
                    self.settings_view(ui);
                } else {
                    self.workbench_view(ui);
                }
            });

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

fn load_windows_ui_settings(
    adapters: &WindowsPlatformAdapters,
    path: &Path,
) -> (WindowsUiSettings, Option<String>) {
    match adapters.filesystem.read(path) {
        Ok(Some(bytes)) => match serde_json::from_slice(&bytes) {
            Ok(settings) => (settings, None),
            Err(error) => (WindowsUiSettings::default(), Some(error.to_string())),
        },
        Ok(None) => (WindowsUiSettings::default(), None),
        Err(error) => (
            WindowsUiSettings::default(),
            Some(error.message().to_owned()),
        ),
    }
}

fn status_badge(ui: &mut egui::Ui, theme: CovioTheme, label: &str, color: egui::Color32) {
    egui::Frame::new()
        .fill(theme.surface_muted)
        .corner_radius(egui::CornerRadius::same(8))
        .inner_margin(egui::Margin::symmetric(8, 3))
        .show(ui, |ui| {
            ui.label(egui::RichText::new(label).size(10.5).color(color));
        });
}

fn settings_back_button(ui: &mut egui::Ui, theme: CovioTheme) -> egui::Response {
    ui.add_sized(
        egui::Vec2::new(28.0, 28.0),
        egui::Button::new(
            egui::RichText::new("‹")
                .size(20.0)
                .color(theme.text_secondary),
        )
        .fill(egui::Color32::TRANSPARENT)
        .stroke(egui::Stroke::NONE)
        .corner_radius(egui::CornerRadius::same(14)),
    )
}

fn settings_tab_button(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    section: SettingsSection,
    label: &str,
    selected: bool,
) -> egui::Response {
    let (rect, response) =
        ui.allocate_exact_size(egui::Vec2::new(68.0, 44.0), egui::Sense::click());
    let accent_alpha = if selected {
        36
    } else if response.hovered() {
        18
    } else {
        0
    };
    if accent_alpha > 0 {
        let [r, g, b, _] = theme.accent.to_array();
        ui.painter().rect_filled(
            rect,
            egui::CornerRadius::same(12),
            egui::Color32::from_rgba_unmultiplied(r, g, b, accent_alpha),
        );
    }
    let color = if selected {
        theme.accent
    } else {
        theme.text_secondary
    };
    paint_settings_icon(
        ui,
        egui::Pos2::new(rect.center().x, rect.top() + 14.0),
        section,
        color,
    );
    ui.painter().text(
        egui::Pos2::new(rect.center().x, rect.bottom() - 5.0),
        egui::Align2::CENTER_BOTTOM,
        label,
        egui::FontId::proportional(10.0),
        color,
    );
    response
}

fn settings_search_field(ui: &mut egui::Ui, theme: CovioTheme, search: &mut String) {
    egui::Frame::new()
        .fill(theme.surface_muted)
        .stroke(egui::Stroke::new(1.0_f32, theme.separator))
        .corner_radius(egui::CornerRadius::same(7))
        .inner_margin(egui::Margin::symmetric(8, 3))
        .show(ui, |ui| {
            ui.set_min_size(egui::Vec2::new(204.0, 20.0));
            ui.horizontal(|ui| {
                paint_search_icon(ui, theme.text_secondary);
                ui.add(
                    egui::TextEdit::singleline(search)
                        .frame(false)
                        .desired_width(174.0)
                        .hint_text(
                            egui::RichText::new("Search settings")
                                .size(11.0)
                                .color(theme.text_secondary),
                        ),
                );
            });
        });
}

fn with_settings_content_width<R>(
    ui: &mut egui::Ui,
    add_contents: impl FnOnce(&mut egui::Ui) -> R,
) -> R {
    let available = ui.available_width();
    let width = available.min(SETTINGS_CONTENT_WIDTH);
    let padding = ((available - width) / 2.0).max(0.0);
    ui.horizontal(|ui| {
        ui.add_space(padding);
        ui.allocate_ui_with_layout(
            egui::Vec2::new(width, ui.available_height()),
            egui::Layout::top_down(egui::Align::Min),
            add_contents,
        )
        .inner
    })
    .inner
}

fn settings_group_title(ui: &mut egui::Ui, theme: CovioTheme, title: &str) {
    ui.add_space(12.0);
    ui.label(
        egui::RichText::new(title)
            .size(11.0)
            .strong()
            .color(theme.text_secondary),
    );
    ui.add_space(7.0);
}

fn settings_group<R>(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    add_contents: impl FnOnce(&mut egui::Ui) -> R,
) -> R {
    theme.settings_group_frame().show(ui, add_contents).inner
}

fn settings_divider(ui: &mut egui::Ui, theme: CovioTheme) {
    let width = ui.available_width();
    let (rect, _) = ui.allocate_exact_size(egui::Vec2::new(width, 1.0), egui::Sense::hover());
    ui.painter().rect_filled(rect, 0, theme.separator);
}

fn settings_label_row(ui: &mut egui::Ui, theme: CovioTheme, label: &str) {
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), SETTINGS_ROW_HEIGHT),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            ui.label(
                egui::RichText::new(label)
                    .size(13.0)
                    .color(theme.text_primary),
            );
        },
    );
}

fn settings_toggle_row(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    label: &str,
    id_source: &str,
    value: &mut bool,
) -> bool {
    let mut changed = false;
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), SETTINGS_ROW_HEIGHT),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            ui.label(
                egui::RichText::new(label)
                    .size(13.0)
                    .color(theme.text_primary),
            );
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if settings_switch(ui, theme, id_source, value).clicked() {
                    *value = !*value;
                    changed = true;
                }
            });
        },
    );
    changed
}

fn settings_switch(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    id_source: &str,
    value: &bool,
) -> egui::Response {
    let (rect, _) = ui.allocate_exact_size(egui::Vec2::new(38.0, 22.0), egui::Sense::hover());
    let response = ui
        .interact(rect, ui.id().with(id_source), egui::Sense::click())
        .on_hover_cursor(egui::CursorIcon::PointingHand);
    let fill = if *value {
        theme.accent
    } else {
        theme.surface_pressed
    };
    ui.painter()
        .rect_filled(rect, egui::CornerRadius::same(11), fill);
    let knob_x = if *value {
        rect.right() - 11.0
    } else {
        rect.left() + 11.0
    };
    ui.painter().circle_filled(
        egui::Pos2::new(knob_x, rect.center().y),
        8.0,
        egui::Color32::WHITE,
    );
    response
}

fn settings_value_row(ui: &mut egui::Ui, theme: CovioTheme, label: &str, value: &str) {
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), SETTINGS_ROW_HEIGHT),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            ui.label(
                egui::RichText::new(label)
                    .size(13.0)
                    .color(theme.text_primary),
            );
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(
                    egui::RichText::new(value)
                        .size(12.0)
                        .color(theme.text_secondary),
                );
            });
        },
    );
}

fn settings_status_row(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    label: &str,
    value: &str,
    color: egui::Color32,
) {
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), SETTINGS_ROW_HEIGHT),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            ui.label(
                egui::RichText::new(label)
                    .size(13.0)
                    .color(theme.text_primary),
            );
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                status_badge(ui, theme, value, color);
            });
        },
    );
}

fn settings_capability_row(ui: &mut egui::Ui, theme: CovioTheme, label: &str, available: bool) {
    settings_status_row(
        ui,
        theme,
        label,
        if available {
            "Available"
        } else {
            "Unavailable"
        },
        if available {
            theme.success
        } else {
            theme.text_disabled
        },
    );
}

fn settings_description_row(ui: &mut egui::Ui, theme: CovioTheme, text: &str) {
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), 36.0),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            ui.label(
                egui::RichText::new(text)
                    .size(11.0)
                    .color(theme.text_secondary),
            );
        },
    );
}

fn settings_warning_row(ui: &mut egui::Ui, theme: CovioTheme, text: &str) {
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), 32.0),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            ui.label(egui::RichText::new(text).size(11.0).color(theme.warning));
        },
    );
}

fn settings_action_row(ui: &mut egui::Ui, add_action: impl FnOnce(&mut egui::Ui)) {
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), SETTINGS_ROW_HEIGHT),
        egui::Layout::right_to_left(egui::Align::Center),
        add_action,
    );
}
fn settings_theme_row(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    current: ThemePreference,
) -> Option<ThemePreference> {
    let mut selected = current;
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), SETTINGS_ROW_HEIGHT),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            ui.label(
                egui::RichText::new("Theme")
                    .size(13.0)
                    .color(theme.text_primary),
            );
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                egui::ComboBox::from_id_salt("settings-theme-picker")
                    .selected_text(theme_preference_label(current))
                    .width(126.0)
                    .show_ui(ui, |ui| {
                        for (preference, label) in [
                            (ThemePreference::System, "System"),
                            (ThemePreference::Light, "Light"),
                            (ThemePreference::Dark, "Dark"),
                        ] {
                            ui.selectable_value(&mut selected, preference, label);
                        }
                    });
            });
        },
    );
    (selected != current).then_some(selected)
}

fn settings_search_result_row(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    section: SettingsSection,
    label: &str,
) -> egui::Response {
    ui.allocate_ui_with_layout(
        egui::Vec2::new(ui.available_width(), SETTINGS_ROW_HEIGHT),
        egui::Layout::left_to_right(egui::Align::Center),
        |ui| {
            let (icon_rect, _) =
                ui.allocate_exact_size(egui::Vec2::new(18.0, 18.0), egui::Sense::hover());
            paint_settings_icon(ui, icon_rect.center(), section, theme.accent);
            ui.add_space(8.0);
            ui.vertical(|ui| {
                ui.label(
                    egui::RichText::new(label)
                        .size(13.0)
                        .color(theme.text_primary),
                );
                ui.label(
                    egui::RichText::new(section.summary())
                        .size(10.5)
                        .color(theme.text_secondary),
                );
            });
        },
    )
    .response
    .interact(egui::Sense::click())
}

fn settings_section_matches(section: SettingsSection, label: &str, query: &str) -> bool {
    label.to_lowercase().contains(query)
        || section.summary().to_lowercase().contains(query)
        || section.search_terms().contains(query)
}

fn theme_preference_label(preference: ThemePreference) -> &'static str {
    match preference {
        ThemePreference::System => "System",
        ThemePreference::Light => "Light",
        ThemePreference::Dark => "Dark",
    }
}

fn status_text(status: &HostStatus) -> &'static str {
    match status {
        HostStatus::Idle => "Idle",
        HostStatus::Loading => "Loading",
        HostStatus::Ready => "Current",
        HostStatus::Error(_) => "Error",
    }
}
fn extension_label(path: &str) -> String {
    Path::new(path)
        .extension()
        .and_then(|extension| extension.to_str())
        .map_or_else(
            || "FILE".to_owned(),
            |extension| extension.to_ascii_uppercase(),
        )
}

fn clipboard_kind_label(kind: covio_core::clipboard::ClipKind) -> &'static str {
    match kind {
        covio_core::clipboard::ClipKind::Text => "Text",
        covio_core::clipboard::ClipKind::Link => "Link",
        covio_core::clipboard::ClipKind::Color => "Color",
        covio_core::clipboard::ClipKind::Image => "Image",
        covio_core::clipboard::ClipKind::Files => "Files",
    }
}

fn content_card(ui: &mut egui::Ui, theme: CovioTheme, add_body: impl FnOnce(&mut egui::Ui)) {
    let width = ui.available_width();
    theme.card_frame().show(ui, |ui| {
        ui.set_min_width((width - 32.0).max(0.0));
        add_body(ui);
    });
}

fn empty_state(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    title: &str,
    detail: &str,
    add_action: impl FnOnce(&mut egui::Ui),
) {
    content_card(ui, theme, |ui| {
        ui.label(
            egui::RichText::new(title)
                .size(16.0)
                .strong()
                .color(theme.text_primary),
        );
        ui.label(egui::RichText::new(detail).color(theme.text_secondary));
        ui.add_space(10.0);
        add_action(ui);
    });
}

fn file_preview(ui: &mut egui::Ui, theme: CovioTheme, extension: &str, tint: egui::Color32) {
    let fill = if theme.dark {
        theme.surface_muted
    } else {
        theme.widget_fill(tint)
    };
    let (rect, _) = ui.allocate_exact_size(
        egui::Vec2::new(ui.available_width(), 82.0),
        egui::Sense::hover(),
    );
    ui.painter()
        .rect_filled(rect, egui::CornerRadius::same(12), fill);
    ui.painter().text(
        rect.center(),
        egui::Align2::CENTER_CENTER,
        extension,
        egui::FontId::proportional(12.0),
        theme.text_secondary,
    );
}

fn type_badge(ui: &mut egui::Ui, theme: CovioTheme, label: &str) {
    egui::Frame::new()
        .fill(theme.surface_muted)
        .stroke(egui::Stroke::new(1.0_f32, theme.separator))
        .corner_radius(egui::CornerRadius::same(20))
        .inner_margin(egui::Margin::symmetric(8, 3))
        .show(ui, |ui| {
            ui.label(
                egui::RichText::new(label)
                    .size(11.0)
                    .color(theme.text_secondary),
            );
        });
}

fn count_label(count: usize, singular: &str, plural: &str) -> String {
    if count == 1 {
        format!("1 {singular}")
    } else {
        format!("{count} {plural}")
    }
}

#[derive(Clone, Debug, PartialEq)]
struct BentoCard {
    title: String,
    detail: String,
    tint: egui::Color32,
    column: usize,
    row: usize,
    columns: usize,
    rows: usize,
}

#[allow(unsafe_code)]
fn local_time_label() -> String {
    let mut time = std::mem::MaybeUninit::<SYSTEMTIME>::zeroed();
    // SAFETY: GetLocalTime writes a complete SYSTEMTIME value to the valid pointer.
    unsafe {
        GetLocalTime(time.as_mut_ptr());
    }
    // SAFETY: The system call initialized the full structure.
    let time = unsafe { time.assume_init() };
    let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    let weekday = weekdays
        .get(time.wDayOfWeek as usize % weekdays.len())
        .copied()
        .unwrap_or("—");
    format!("{:02}:{:02} · {weekday}", time.wHour, time.wMinute)
}

fn home_bento_cards(snapshot: &HostSnapshot) -> Vec<BentoCard> {
    vec![
        BentoCard {
            title: "Now".to_owned(),
            detail: local_time_label(),
            tint: WIDGET_TINT_AMBER,
            column: 0,
            row: 0,
            columns: 2,
            rows: 1,
        },
        BentoCard {
            title: "Battery".to_owned(),
            detail: "—".to_owned(),
            tint: WIDGET_TINT_MINT,
            column: 2,
            row: 0,
            columns: 1,
            rows: 1,
        },
        BentoCard {
            title: "Transfer".to_owned(),
            detail: "—".to_owned(),
            tint: WIDGET_TINT_SKY,
            column: 0,
            row: 1,
            columns: 2,
            rows: 1,
        },
        BentoCard {
            title: "Quick actions".to_owned(),
            detail: "—".to_owned(),
            tint: WIDGET_TINT_APRICOT,
            column: 3,
            row: 0,
            columns: 1,
            rows: 2,
        },
        BentoCard {
            title: "Recent screenshots".to_owned(),
            detail: snapshot.shelf_item_count.to_string(),
            tint: WIDGET_TINT_ROSE,
            column: 0,
            row: 2,
            columns: 2,
            rows: 2,
        },
        BentoCard {
            title: "Monitor".to_owned(),
            detail: "—".to_owned(),
            tint: WIDGET_TINT_SLATE,
            column: 2,
            row: 1,
            columns: 1,
            rows: 1,
        },
    ]
}

fn bento_grid(ui: &mut egui::Ui, theme: CovioTheme, cards: &[BentoCard]) {
    let width = ui.available_width().min(PAGE_MAX_WIDTH);
    if width < 720.0 {
        for card in cards {
            let (rect, _) = ui.allocate_exact_size(
                egui::Vec2::new(width, BENTO_ROW_HEIGHT),
                egui::Sense::hover(),
            );
            draw_bento_card(ui, theme, rect, card);
            ui.add_space(BENTO_GAP);
        }
        return;
    }

    let column_width =
        (width - BENTO_GAP * (BENTO_COLUMNS.saturating_sub(1) as f32)) / BENTO_COLUMNS as f32;
    let height = BENTO_ROW_HEIGHT * BENTO_MAX_ROWS as f32
        + BENTO_GAP * BENTO_MAX_ROWS.saturating_sub(1) as f32;
    let (grid_rect, _) =
        ui.allocate_exact_size(egui::Vec2::new(width, height), egui::Sense::hover());
    for card in cards {
        let rect = bento_card_rect(grid_rect, column_width, card);
        draw_bento_card(ui, theme, rect, card);
    }
}

fn bento_card_rect(grid_rect: egui::Rect, column_width: f32, card: &BentoCard) -> egui::Rect {
    let x = grid_rect.left() + card.column as f32 * (column_width + BENTO_GAP);
    let y = grid_rect.top() + card.row as f32 * (BENTO_ROW_HEIGHT + BENTO_GAP);
    let card_width =
        card.columns as f32 * column_width + BENTO_GAP * card.columns.saturating_sub(1) as f32;
    let card_height =
        card.rows as f32 * BENTO_ROW_HEIGHT + BENTO_GAP * card.rows.saturating_sub(1) as f32;
    egui::Rect::from_min_size(
        egui::Pos2::new(x, y),
        egui::Vec2::new(card_width, card_height),
    )
}

fn draw_bento_card(ui: &mut egui::Ui, theme: CovioTheme, rect: egui::Rect, card: &BentoCard) {
    ui.scope_builder(egui::UiBuilder::new().max_rect(rect), |ui| {
        egui::Frame::new()
            .fill(theme.widget_fill(card.tint))
            .corner_radius(egui::CornerRadius::same(16))
            .inner_margin(egui::Margin::same(BENTO_CARD_PADDING as i8))
            .show(ui, |ui| {
                ui.set_min_size(egui::Vec2::new(
                    (rect.width() - BENTO_CARD_PADDING * 2.0).max(0.0),
                    (rect.height() - BENTO_CARD_PADDING * 2.0).max(0.0),
                ));
                ui.label(
                    egui::RichText::new(&card.title)
                        .size(13.0)
                        .strong()
                        .color(theme.text_primary),
                );
                ui.add_space(4.0);
                ui.label(
                    egui::RichText::new(&card.detail)
                        .size(11.0)
                        .color(theme.text_secondary),
                );
            });
    });
}

fn paint_search_icon(ui: &mut egui::Ui, color: egui::Color32) {
    let (rect, _) = ui.allocate_exact_size(egui::Vec2::splat(14.0), egui::Sense::hover());
    let center = rect.center() + egui::Vec2::new(-1.0, -1.0);
    ui.painter()
        .circle_stroke(center, 4.0, egui::Stroke::new(1.4_f32, color));
    ui.painter().line_segment(
        [
            center + egui::Vec2::new(3.0, 3.0),
            rect.center() + egui::Vec2::new(6.0, 6.0),
        ],
        egui::Stroke::new(1.4_f32, color),
    );
}

fn paint_settings_icon(
    ui: &mut egui::Ui,
    center: egui::Pos2,
    section: SettingsSection,
    color: egui::Color32,
) {
    let painter = ui.painter();
    match section {
        SettingsSection::Overview => {
            let top = egui::Rect::from_center_size(
                center + egui::Vec2::new(0.0, -3.5),
                egui::Vec2::new(14.0, 6.0),
            );
            let bottom = egui::Rect::from_center_size(
                center + egui::Vec2::new(0.0, 3.5),
                egui::Vec2::new(14.0, 6.0),
            );
            painter.rect_filled(top, egui::CornerRadius::same(3), color);
            painter.circle_filled(
                egui::Pos2::new(top.right() - 3.0, top.center().y),
                2.0,
                egui::Color32::WHITE,
            );
            painter.rect_filled(bottom, egui::CornerRadius::same(3), color);
            painter.circle_filled(
                egui::Pos2::new(bottom.left() + 3.0, bottom.center().y),
                2.0,
                egui::Color32::WHITE,
            );
        }
        SettingsSection::Appearance => {
            painter.circle_stroke(center, 7.0, egui::Stroke::new(1.5_f32, color));
            painter.line_segment(
                [
                    center + egui::Vec2::new(0.0, -7.0),
                    center + egui::Vec2::new(0.0, 7.0),
                ],
                egui::Stroke::new(1.6_f32, color),
            );
        }
        SettingsSection::Triggers => {
            painter.add(egui::Shape::convex_polygon(
                vec![
                    center + egui::Vec2::new(1.0, -8.0),
                    center + egui::Vec2::new(-5.0, 1.0),
                    center + egui::Vec2::new(-1.0, 1.0),
                    center + egui::Vec2::new(-2.0, 8.0),
                    center + egui::Vec2::new(6.0, -2.0),
                    center + egui::Vec2::new(1.5, -2.0),
                ],
                color,
                egui::Stroke::NONE,
            ));
        }
        SettingsSection::Capabilities => {
            for offset in [
                egui::Vec2::new(-4.0, -4.0),
                egui::Vec2::new(4.0, -4.0),
                egui::Vec2::new(-4.0, 4.0),
                egui::Vec2::new(4.0, 4.0),
            ] {
                painter.rect_filled(
                    egui::Rect::from_center_size(center + offset, egui::Vec2::splat(5.0)),
                    egui::CornerRadius::same(1),
                    color,
                );
            }
        }
        SettingsSection::Updates => {
            painter.circle_stroke(center, 7.0, egui::Stroke::new(1.5_f32, color));
            painter.line_segment(
                [
                    center + egui::Vec2::new(4.0, -7.0),
                    center + egui::Vec2::new(8.0, -7.0),
                ],
                egui::Stroke::new(1.5_f32, color),
            );
            painter.line_segment(
                [
                    center + egui::Vec2::new(8.0, -7.0),
                    center + egui::Vec2::new(8.0, -3.0),
                ],
                egui::Stroke::new(1.5_f32, color),
            );
        }
    }
}
fn workbench_search_field(ui: &mut egui::Ui, theme: CovioTheme, search: &mut String) {
    egui::Frame::new()
        .fill(theme.surface_hover)
        .stroke(egui::Stroke::new(1.0_f32, theme.separator))
        .corner_radius(egui::CornerRadius::same(15))
        .inner_margin(egui::Margin::symmetric(10, 4))
        .show(ui, |ui| {
            ui.set_min_size(egui::Vec2::new(
                HUB_SEARCH_WIDTH - 20.0,
                HUB_NAV_HEIGHT - 8.0,
            ));
            ui.horizontal(|ui| {
                paint_search_icon(ui, theme.text_secondary);
                ui.add(
                    egui::TextEdit::singleline(search)
                        .frame(false)
                        .desired_width(HUB_SEARCH_WIDTH - 50.0)
                        .hint_text(
                            egui::RichText::new("Search")
                                .size(12.0)
                                .color(theme.text_secondary),
                        ),
                );
            });
        });
}

fn workbench_action_button(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    label: &str,
    width: f32,
) -> egui::Response {
    ui.add_sized(
        egui::Vec2::new(width, HUB_NAV_HEIGHT),
        egui::Button::new(
            egui::RichText::new(label)
                .size(12.0)
                .color(theme.text_primary),
        )
        .fill(egui::Color32::TRANSPARENT)
        .stroke(egui::Stroke::NONE)
        .corner_radius(egui::CornerRadius::same(15)),
    )
}

fn workbench_nav_button(
    ui: &mut egui::Ui,
    theme: CovioTheme,
    label: &str,
    selected: bool,
    width: f32,
) -> egui::Response {
    let text_color = if selected {
        theme.text_on_accent
    } else {
        theme.text_secondary
    };
    ui.add_sized(
        egui::Vec2::new(width, HUB_NAV_HEIGHT),
        egui::Button::new(egui::RichText::new(label).size(12.0).color(text_color))
            .fill(if selected {
                theme.accent
            } else {
                egui::Color32::TRANSPARENT
            })
            .stroke(egui::Stroke::NONE)
            .corner_radius(egui::CornerRadius::same(15)),
    )
}
fn with_page_width<R>(ui: &mut egui::Ui, add_contents: impl FnOnce(&mut egui::Ui) -> R) -> R {
    let available = ui.available_width();
    let width = available.min(PAGE_MAX_WIDTH);
    let padding = ((available - width) / 2.0).max(0.0);
    ui.horizontal(|ui| {
        ui.add_space(padding);
        ui.allocate_ui_with_layout(
            egui::Vec2::new(width, ui.available_height()),
            egui::Layout::top_down(egui::Align::Min),
            add_contents,
        )
        .inner
    })
    .inner
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

fn window_inner_size(view: HostView) -> [f32; 2] {
    if view == HostView::Settings {
        [900.0, 640.0]
    } else {
        [HUB_PANEL_WIDTH, 880.0]
    }
}

fn instance_name_for_arguments(arguments: &[String]) -> &'static str {
    if screenshot_path_from_arguments(arguments).is_some() {
        SCREENSHOT_INSTANCE_NAME
    } else {
        INSTANCE_NAME
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

fn settings_section_from_arguments(arguments: &[String]) -> Option<SettingsSection> {
    let value = arguments
        .iter()
        .position(|argument| argument == "--settings-section")
        .and_then(|index| arguments.get(index + 1))
        .map(String::as_str)?;
    match value {
        "overview" => Some(SettingsSection::Overview),
        "appearance" => Some(SettingsSection::Appearance),
        "triggers" => Some(SettingsSection::Triggers),
        "capabilities" => Some(SettingsSection::Capabilities),
        "updates" => Some(SettingsSection::Updates),
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

struct HubHotKey {
    manager: GlobalHotKeyManager,
    hotkey: HotKey,
}

impl HubHotKey {
    fn register() -> Result<Self, String> {
        let manager = GlobalHotKeyManager::new()
            .map_err(|error| format!("Cannot create the global hotkey manager: {error}"))?;
        let hotkey = hub_toggle_hotkey();
        if let Err(error) = manager.register(hotkey) {
            eprintln!("{HUB_TOGGLE_SHORTCUT} registration failed: {error}");
            return Err(format!(
                "{HUB_TOGGLE_SHORTCUT} is unavailable. Another app owns it."
            ));
        }
        Ok(Self { manager, hotkey })
    }

    fn id(&self) -> u32 {
        self.hotkey.id()
    }
}

impl Drop for HubHotKey {
    fn drop(&mut self) {
        let _ = self.manager.unregister(self.hotkey);
    }
}

enum TrayAction {
    OpenScreenshots,
    OpenSettings,
    ToggleWindow,
    Quit,
}

struct TrayController {
    _tray: TrayIcon,
    screenshots_id: MenuId,
    settings_id: MenuId,
    quit_id: MenuId,
}

impl TrayController {
    fn new() -> Result<Self, String> {
        let menu = Menu::new();
        let screenshots = MenuItem::with_id("show-screenshots", "Show screenshots", true, None);
        let settings = MenuItem::with_id("settings", "Settings", true, None);
        let separator = PredefinedMenuItem::separator();
        let quit = MenuItem::with_id("quit", "Quit Covio", true, None);
        menu.append_items(&[&screenshots, &settings, &separator, &quit])
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
            screenshots_id: screenshots.id().clone(),
            settings_id: settings.id().clone(),
            quit_id: quit.id().clone(),
        })
    }

    fn poll(&self) -> Option<TrayAction> {
        while let Ok(event) = MenuEvent::receiver().try_recv() {
            if event.id == self.screenshots_id {
                return Some(TrayAction::OpenScreenshots);
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

fn hub_toggle_hotkey() -> HotKey {
    HotKey::new(
        Some(GlobalHotKeyModifiers::CONTROL | GlobalHotKeyModifiers::ALT),
        Code::KeyT,
    )
}

fn is_hub_toggle_event(event: GlobalHotKeyEvent, target_id: Option<u32>) -> bool {
    target_id == Some(event.id()) && event.state() == HotKeyState::Pressed
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
    fn settings_section_argument_selects_product_sections() {
        let arguments = vec![
            "covio-windows.exe".to_owned(),
            "--settings-section".to_owned(),
            "triggers".to_owned(),
        ];
        assert_eq!(
            settings_section_from_arguments(&arguments),
            Some(SettingsSection::Triggers)
        );
    }

    #[test]
    fn settings_sections_cover_every_section_once() {
        let sections: Vec<SettingsSection> = SETTINGS_SECTIONS
            .iter()
            .map(|(section, _)| *section)
            .collect();
        assert_eq!(
            sections,
            vec![
                SettingsSection::Overview,
                SettingsSection::Appearance,
                SettingsSection::Triggers,
                SettingsSection::Capabilities,
                SettingsSection::Updates,
            ]
        );
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
    fn hub_hotkey_is_control_alt_t() {
        let hotkey = hub_toggle_hotkey();
        assert_eq!(hotkey.key, Code::KeyT);
        assert_eq!(
            hotkey.mods,
            GlobalHotKeyModifiers::CONTROL | GlobalHotKeyModifiers::ALT
        );
    }

    #[test]
    fn hub_toggle_ignores_release_events() {
        let pressed = GlobalHotKeyEvent {
            id: 7,
            state: HotKeyState::Pressed,
        };
        let released = GlobalHotKeyEvent {
            id: pressed.id,
            state: HotKeyState::Released,
        };
        assert!(is_hub_toggle_event(pressed, Some(7)));
        assert!(!is_hub_toggle_event(released, Some(7)));
        assert!(!is_hub_toggle_event(pressed, Some(8)));
    }

    #[test]
    fn file_extension_label_is_bounded_and_uppercase() {
        assert_eq!(extension_label("Covio demo.png"), "PNG");
        assert_eq!(extension_label("README"), "FILE");
    }

    #[test]
    fn dashboard_counts_use_singular_and_plural_labels() {
        assert_eq!(count_label(1, "screenshot", "screenshots"), "1 screenshot");
        assert_eq!(count_label(2, "screenshot", "screenshots"), "2 screenshots");
    }

    #[test]
    fn bento_metrics_match_the_macos_baseline() {
        assert_eq!(BENTO_COLUMNS, 4);
        assert_eq!(BENTO_ROW_HEIGHT, 96.0);
        assert_eq!(BENTO_GAP, 12.0);
        assert_eq!(PAGE_MAX_WIDTH, 912.0);
    }

    #[test]
    fn bento_card_rects_match_the_macos_spans() {
        let card = BentoCard {
            title: "Quick actions".to_owned(),
            detail: "—".to_owned(),
            tint: WIDGET_TINT_APRICOT,
            column: 3,
            row: 0,
            columns: 1,
            rows: 2,
        };
        let rect = bento_card_rect(
            egui::Rect::from_min_size(egui::Pos2::ZERO, egui::Vec2::splat(912.0)),
            219.0,
            &card,
        );
        assert_eq!(rect.min, egui::Pos2::new(693.0, 0.0));
        assert_eq!(rect.size(), egui::Vec2::new(219.0, 204.0));
    }

    #[test]
    fn settings_search_matches_labels_and_summaries() {
        assert!(settings_section_matches(
            SettingsSection::Triggers,
            "Triggers",
            "top edge"
        ));
        assert!(settings_section_matches(
            SettingsSection::Capabilities,
            "Capabilities",
            "adapter"
        ));
        assert!(!settings_section_matches(
            SettingsSection::Overview,
            "Overview",
            "adapter"
        ));
    }

    #[test]
    fn navigation_items_cover_every_product_view_once() {
        let mut views = vec![HostView::Home];
        views.extend(WORKBENCH_TABS.iter().map(|(view, _)| *view));
        views.push(HostView::Settings);
        assert_eq!(
            views,
            vec![
                HostView::Home,
                HostView::Shelf,
                HostView::Clipboard,
                HostView::Workspace,
                HostView::Settings,
            ]
        );
    }

    #[test]
    fn window_size_tracks_the_macos_surface() {
        assert_eq!(window_inner_size(HostView::Home), [960.0, 880.0]);
        assert_eq!(window_inner_size(HostView::Settings), [900.0, 640.0]);
    }

    #[test]
    fn screenshot_mode_uses_a_separate_single_instance_lock() {
        let screenshot = vec![
            "covio-windows.exe".to_owned(),
            "--screenshot".to_owned(),
            "home.png".to_owned(),
        ];
        assert_eq!(
            instance_name_for_arguments(&screenshot),
            SCREENSHOT_INSTANCE_NAME
        );
        assert_eq!(instance_name_for_arguments(&[]), INSTANCE_NAME);
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
