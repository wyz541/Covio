//! Bounded Windows capability adapters used by the native Rust host.

use crate::{PlatformError, PlatformErrorCode};
use std::path::PathBuf;

/// Maximum text size accepted by the clipboard adapter.
pub const MAX_CLIPBOARD_TEXT_BYTES: usize = 16 * 1024 * 1024;
/// Maximum number of files returned by one picker request.
pub const MAX_PICKED_FILES: usize = 64;
/// Maximum notification title length in bytes.
pub const MAX_NOTIFICATION_TITLE_BYTES: usize = 128;
/// Maximum notification body length in bytes.
pub const MAX_NOTIFICATION_BODY_BYTES: usize = 4096;
/// Maximum startup registry value name length in bytes.
pub const MAX_STARTUP_NAME_BYTES: usize = 128;

/// One native file-picker request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FilePickerRequest {
    /// Dialog title.
    pub title: String,
    /// Lowercase extensions without a leading dot.
    pub extensions: Vec<String>,
    /// Whether the user may select more than one file.
    pub multiple: bool,
}

impl FilePickerRequest {
    /// Creates a single-file request.
    #[must_use]
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            extensions: Vec::new(),
            multiple: false,
        }
    }

    /// Adds a file extension filter.
    #[must_use]
    pub fn with_extensions(
        mut self,
        extensions: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        self.extensions = extensions.into_iter().map(Into::into).collect();
        self
    }

    /// Selects single-file or multi-file mode.
    #[must_use]
    pub const fn multiple(mut self, multiple: bool) -> Self {
        self.multiple = multiple;
        self
    }

    /// Validates the request before it reaches the OS adapter.
    pub fn validate(&self) -> Result<(), PlatformError> {
        if self.title.is_empty() || self.title.len() > 256 || self.title.contains('\0') {
            return Err(PlatformError::invalid_argument(
                "file picker title is invalid",
            ));
        }
        if self.extensions.len() > 16 {
            return Err(PlatformError::invalid_argument(
                "file picker has too many filters",
            ));
        }
        for extension in &self.extensions {
            if extension.is_empty()
                || extension.len() > 16
                || extension.starts_with('.')
                || !extension
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'-'))
            {
                return Err(PlatformError::invalid_argument(
                    "file picker extension is invalid",
                ));
            }
        }
        Ok(())
    }
}

/// Native file picker.
pub trait FilePicker {
    /// Returns selected paths. `None` means the user canceled the dialog.
    fn pick_files(
        &self,
        request: &FilePickerRequest,
    ) -> Result<Option<Vec<PathBuf>>, PlatformError>;
}

/// System clipboard.
pub trait Clipboard {
    /// Reads text. `None` means the clipboard has no text value.
    fn read_text(&self) -> Result<Option<String>, PlatformError>;
    /// Writes text.
    fn write_text(&self, text: &str) -> Result<(), PlatformError>;
    /// Clears the clipboard.
    fn clear(&self) -> Result<(), PlatformError>;
}

/// One user notification.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotificationRequest {
    /// Notification title.
    pub title: String,
    /// Notification body.
    pub body: String,
}

impl NotificationRequest {
    /// Creates one notification.
    #[must_use]
    pub fn new(title: impl Into<String>, body: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            body: body.into(),
        }
    }

    /// Validates the notification before it reaches the OS adapter.
    pub fn validate(&self) -> Result<(), PlatformError> {
        if self.title.is_empty()
            || self.title.len() > MAX_NOTIFICATION_TITLE_BYTES
            || self.title.contains('\0')
            || self.body.len() > MAX_NOTIFICATION_BODY_BYTES
            || self.body.contains('\0')
        {
            return Err(PlatformError::invalid_argument(
                "notification payload is invalid",
            ));
        }
        Ok(())
    }
}

/// User notification adapter.
pub trait Notifier {
    /// Shows one notification.
    fn notify(&self, request: &NotificationRequest) -> Result<(), PlatformError>;
}

/// One current-user startup registration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StartupSpec {
    /// Registry value name.
    pub app_name: String,
    /// Absolute executable path.
    pub executable: PathBuf,
    /// Startup arguments.
    pub arguments: Vec<String>,
}

impl StartupSpec {
    /// Creates one startup specification.
    #[must_use]
    pub fn new(app_name: impl Into<String>, executable: impl Into<PathBuf>) -> Self {
        Self {
            app_name: app_name.into(),
            executable: executable.into(),
            arguments: Vec::new(),
        }
    }

    /// Adds startup arguments.
    #[must_use]
    pub fn with_arguments(
        mut self,
        arguments: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        self.arguments = arguments.into_iter().map(Into::into).collect();
        self
    }

    /// Validates the registration before it reaches the OS adapter.
    pub fn validate(&self) -> Result<(), PlatformError> {
        if self.app_name.is_empty()
            || self.app_name.len() > MAX_STARTUP_NAME_BYTES
            || self.app_name.contains('\0')
            || !self.executable.is_absolute()
            || !self.executable.is_file()
            || self
                .arguments
                .iter()
                .any(|argument| argument.contains('\0'))
        {
            return Err(PlatformError::invalid_argument(
                "startup registration is invalid",
            ));
        }
        Ok(())
    }
}

/// Current-user startup registration adapter.
pub trait StartupRegistration {
    /// Enables startup registration.
    fn enable(&self, spec: &StartupSpec) -> Result<(), PlatformError>;
    /// Disables startup registration.
    fn disable(&self, spec: &StartupSpec) -> Result<(), PlatformError>;
    /// Reports whether startup is registered and enabled.
    fn is_enabled(&self, spec: &StartupSpec) -> Result<bool, PlatformError>;
}

/// Screenshot source discovery.
pub trait ScreenshotDirectory {
    /// Returns the lowest existing configured screenshot directory.
    fn directory(&self) -> Result<PathBuf, PlatformError>;
}

/// One updater handoff request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateHandoffRequest {
    /// Absolute updater executable path.
    pub executable: PathBuf,
    /// Updater arguments.
    pub arguments: Vec<String>,
}

impl UpdateHandoffRequest {
    /// Creates one updater request.
    #[must_use]
    pub fn new(executable: impl Into<PathBuf>) -> Self {
        Self {
            executable: executable.into(),
            arguments: Vec::new(),
        }
    }

    /// Adds updater arguments.
    #[must_use]
    pub fn with_arguments(
        mut self,
        arguments: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        self.arguments = arguments.into_iter().map(Into::into).collect();
        self
    }

    /// Validates the updater before a process is started.
    pub fn validate(&self) -> Result<(), PlatformError> {
        let Some(name) = self.executable.file_name().and_then(|name| name.to_str()) else {
            return Err(PlatformError::invalid_argument(
                "updater executable is invalid",
            ));
        };
        let allowed_name = name.eq_ignore_ascii_case("CovioUpdater.exe")
            || name.eq_ignore_ascii_case("CovioUpdaterLauncher.exe");
        if !allowed_name
            || !self.executable.is_absolute()
            || !self.executable.is_file()
            || self
                .arguments
                .iter()
                .any(|argument| argument.contains('\0'))
        {
            return Err(PlatformError::invalid_argument(
                "updater executable is invalid",
            ));
        }
        Ok(())
    }
}

/// Updater process handoff adapter.
pub trait UpdateHandoff {
    /// Starts the updater without waiting for it.
    fn launch(&self, request: &UpdateHandoffRequest) -> Result<(), PlatformError>;
}

/// A typed unavailable implementation for capabilities the current platform
/// does not expose.
#[derive(Debug, Clone, Copy, Default)]
pub struct UnavailablePlatformAdapter;

impl FilePicker for UnavailablePlatformAdapter {
    fn pick_files(
        &self,
        _request: &FilePickerRequest,
    ) -> Result<Option<Vec<PathBuf>>, PlatformError> {
        Err(unavailable())
    }
}

impl Clipboard for UnavailablePlatformAdapter {
    fn read_text(&self) -> Result<Option<String>, PlatformError> {
        Err(unavailable())
    }

    fn write_text(&self, _text: &str) -> Result<(), PlatformError> {
        Err(unavailable())
    }

    fn clear(&self) -> Result<(), PlatformError> {
        Err(unavailable())
    }
}

impl Notifier for UnavailablePlatformAdapter {
    fn notify(&self, _request: &NotificationRequest) -> Result<(), PlatformError> {
        Err(unavailable())
    }
}

impl StartupRegistration for UnavailablePlatformAdapter {
    fn enable(&self, _spec: &StartupSpec) -> Result<(), PlatformError> {
        Err(unavailable())
    }

    fn disable(&self, _spec: &StartupSpec) -> Result<(), PlatformError> {
        Err(unavailable())
    }

    fn is_enabled(&self, _spec: &StartupSpec) -> Result<bool, PlatformError> {
        Err(unavailable())
    }
}

impl ScreenshotDirectory for UnavailablePlatformAdapter {
    fn directory(&self) -> Result<PathBuf, PlatformError> {
        Err(unavailable())
    }
}

impl UpdateHandoff for UnavailablePlatformAdapter {
    fn launch(&self, _request: &UpdateHandoffRequest) -> Result<(), PlatformError> {
        Err(unavailable())
    }
}

/// Windows screenshot directory discovery.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WindowsScreenshotDirectory {
    candidates: Vec<PathBuf>,
}

impl WindowsScreenshotDirectory {
    /// Builds a locator from ordered candidate directories.
    #[must_use]
    pub fn with_candidates(candidates: impl IntoIterator<Item = PathBuf>) -> Self {
        Self {
            candidates: candidates.into_iter().collect(),
        }
    }

    /// Builds candidates from `USERPROFILE` and `OneDrive`.
    #[must_use]
    pub fn from_environment() -> Self {
        let mut candidates = Vec::new();
        if let Some(profile) = std::env::var_os("USERPROFILE") {
            candidates.push(PathBuf::from(profile).join("Pictures").join("Screenshots"));
        }
        if let Some(one_drive) = std::env::var_os("OneDrive") {
            candidates.push(
                PathBuf::from(one_drive)
                    .join("Pictures")
                    .join("Screenshots"),
            );
        }
        Self::with_candidates(candidates)
    }
}

impl ScreenshotDirectory for WindowsScreenshotDirectory {
    fn directory(&self) -> Result<PathBuf, PlatformError> {
        self.candidates
            .iter()
            .find(|candidate| candidate.is_absolute() && candidate.is_dir())
            .cloned()
            .ok_or_else(|| PlatformError::unavailable("screenshot directory is unavailable"))
    }
}

#[cfg(target_os = "windows")]
mod system {
    use super::{
        Clipboard, FilePicker, FilePickerRequest, MAX_CLIPBOARD_TEXT_BYTES, MAX_PICKED_FILES,
        NotificationRequest, Notifier, StartupRegistration, StartupSpec, UpdateHandoff,
        UpdateHandoffRequest,
    };
    use crate::{APP_ID, PlatformError};
    use auto_launch::{AutoLaunch, WindowsEnableMode};
    use std::path::PathBuf;
    use std::process::Command;

    /// Windows system clipboard adapter.
    #[derive(Debug, Clone, Copy, Default)]
    pub struct WindowsClipboard;

    impl Clipboard for WindowsClipboard {
        fn read_text(&self) -> Result<Option<String>, PlatformError> {
            let mut clipboard = arboard::Clipboard::new().map_err(clipboard_error)?;
            match clipboard.get_text() {
                Ok(text) => Ok(Some(text)),
                Err(arboard::Error::ContentNotAvailable) => Ok(None),
                Err(error) => Err(clipboard_error(error)),
            }
        }

        fn write_text(&self, text: &str) -> Result<(), PlatformError> {
            if text.len() > MAX_CLIPBOARD_TEXT_BYTES {
                return Err(PlatformError::invalid_argument(
                    "clipboard text exceeds the size limit",
                ));
            }
            let mut clipboard = arboard::Clipboard::new().map_err(clipboard_error)?;
            clipboard.set_text(text).map_err(clipboard_error)
        }

        fn clear(&self) -> Result<(), PlatformError> {
            let mut clipboard = arboard::Clipboard::new().map_err(clipboard_error)?;
            clipboard.clear().map_err(clipboard_error)
        }
    }

    fn clipboard_error(error: arboard::Error) -> PlatformError {
        match error {
            arboard::Error::ClipboardNotSupported => {
                PlatformError::unavailable("system clipboard is unavailable")
            }
            arboard::Error::ClipboardOccupied => {
                PlatformError::io("system clipboard is busy", true)
            }
            _ => PlatformError::io("system clipboard operation failed", true),
        }
    }

    /// Windows native file picker.
    #[derive(Debug, Clone, Copy, Default)]
    pub struct WindowsFilePicker;

    impl FilePicker for WindowsFilePicker {
        fn pick_files(
            &self,
            request: &FilePickerRequest,
        ) -> Result<Option<Vec<PathBuf>>, PlatformError> {
            request.validate()?;
            let mut dialog = rfd::FileDialog::new().set_title(request.title.clone());
            if !request.extensions.is_empty() {
                dialog = dialog.add_filter("Supported files", &request.extensions);
            }
            let selected = if request.multiple {
                dialog.pick_files()
            } else {
                dialog.pick_file().map(|path| vec![path])
            };
            if selected
                .as_ref()
                .is_some_and(|paths| paths.len() > MAX_PICKED_FILES)
            {
                return Err(PlatformError::invalid_argument(
                    "file picker returned too many files",
                ));
            }
            Ok(selected)
        }
    }

    /// Windows toast notification adapter.
    #[derive(Debug, Clone)]
    pub struct WindowsToastNotifier {
        app_id: String,
    }

    impl WindowsToastNotifier {
        /// Creates one notifier for an AppUserModelID.
        pub fn new(app_id: impl Into<String>) -> Result<Self, PlatformError> {
            let app_id = app_id.into();
            if app_id.is_empty() || app_id.len() > 256 || app_id.contains('\0') {
                return Err(PlatformError::invalid_argument(
                    "notification app identifier is invalid",
                ));
            }
            Ok(Self { app_id })
        }
    }

    impl Default for WindowsToastNotifier {
        fn default() -> Self {
            Self {
                app_id: APP_ID.to_owned(),
            }
        }
    }

    impl Notifier for WindowsToastNotifier {
        fn notify(&self, request: &NotificationRequest) -> Result<(), PlatformError> {
            request.validate()?;
            tauri_winrt_notification::Toast::new(&self.app_id)
                .title(&request.title)
                .text1(&request.body)
                .show()
                .map_err(|_| PlatformError::io("notification could not be shown", true))
        }
    }

    /// Windows current-user startup adapter.
    #[derive(Debug, Clone, Copy, Default)]
    pub struct WindowsStartupRegistration;

    impl StartupRegistration for WindowsStartupRegistration {
        fn enable(&self, spec: &StartupSpec) -> Result<(), PlatformError> {
            startup(spec)?.enable().map_err(startup_error)
        }

        fn disable(&self, spec: &StartupSpec) -> Result<(), PlatformError> {
            startup(spec)?.disable().map_err(startup_error)
        }

        fn is_enabled(&self, spec: &StartupSpec) -> Result<bool, PlatformError> {
            startup(spec)?.is_enabled().map_err(startup_error)
        }
    }

    fn startup(spec: &StartupSpec) -> Result<AutoLaunch, PlatformError> {
        spec.validate()?;
        let executable = spec
            .executable
            .to_str()
            .ok_or_else(|| PlatformError::invalid_argument("startup executable is invalid"))?;
        Ok(AutoLaunch::new(
            &spec.app_name,
            executable,
            WindowsEnableMode::CurrentUser,
            &spec.arguments,
        ))
    }

    fn startup_error(_error: auto_launch::Error) -> PlatformError {
        PlatformError::io("startup registration failed", false)
    }

    /// Windows updater process handoff.
    #[derive(Debug, Clone, Copy, Default)]
    pub struct WindowsUpdateHandoff;

    impl UpdateHandoff for WindowsUpdateHandoff {
        fn launch(&self, request: &UpdateHandoffRequest) -> Result<(), PlatformError> {
            request.validate()?;
            let mut command = Command::new(&request.executable);
            command.args(&request.arguments);
            #[cfg(target_os = "windows")]
            {
                use std::os::windows::process::CommandExt;
                const CREATE_NO_WINDOW: u32 = 0x0800_0000;
                command.creation_flags(CREATE_NO_WINDOW);
            }
            command
                .spawn()
                .map(|_child| ())
                .map_err(|_| PlatformError::io("updater could not start", true))
        }
    }
}

#[cfg(target_os = "windows")]
pub use system::{
    WindowsClipboard, WindowsFilePicker, WindowsStartupRegistration, WindowsToastNotifier,
    WindowsUpdateHandoff,
};

/// Complete native adapter set for the Windows host.
#[cfg(target_os = "windows")]
pub struct WindowsPlatformAdapters {
    /// Atomic filesystem adapter.
    pub filesystem: crate::StdFileStore,
    /// Windows Credential Manager adapter.
    pub credentials: crate::WindowsCredentialStore,
    /// System clipboard adapter.
    pub clipboard: WindowsClipboard,
    /// Native file picker.
    pub file_picker: WindowsFilePicker,
    /// Windows toast notifications.
    pub notifications: WindowsToastNotifier,
    /// Current-user startup registration.
    pub startup: WindowsStartupRegistration,
    /// Screenshot source discovery.
    pub screenshots: WindowsScreenshotDirectory,
    /// Updater process handoff.
    pub update_handoff: WindowsUpdateHandoff,
    /// Current capability inventory.
    pub capabilities: crate::WindowsCapabilitySet,
}

#[cfg(target_os = "windows")]
impl Default for WindowsPlatformAdapters {
    fn default() -> Self {
        Self {
            filesystem: crate::StdFileStore::new(),
            credentials: crate::WindowsCredentialStore::default(),
            clipboard: WindowsClipboard,
            file_picker: WindowsFilePicker,
            notifications: WindowsToastNotifier::default(),
            startup: WindowsStartupRegistration,
            screenshots: WindowsScreenshotDirectory::from_environment(),
            update_handoff: WindowsUpdateHandoff,
            capabilities: crate::WindowsCapabilitySet::default(),
        }
    }
}

fn unavailable() -> PlatformError {
    PlatformError::new(
        PlatformErrorCode::Unavailable,
        "platform capability is unavailable",
        false,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temporary_directory() -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "covio-windows-adapters-{}-{nonce}",
            std::process::id()
        ))
    }

    #[test]
    fn unavailable_adapter_never_reports_false_success() {
        let adapter = UnavailablePlatformAdapter;
        let error = adapter.read_text().expect_err("clipboard unavailable");
        assert_eq!(error.code(), PlatformErrorCode::Unavailable);
        let error = adapter.directory().expect_err("screenshot unavailable");
        assert_eq!(error.code(), PlatformErrorCode::Unavailable);
    }

    #[test]
    fn screenshot_locator_uses_the_first_existing_absolute_directory() {
        let root = temporary_directory();
        let missing = root.join("missing");
        let found = root.join("found");
        std::fs::create_dir_all(&found).expect("create screenshot directory");
        let locator = WindowsScreenshotDirectory::with_candidates([missing, found.clone()]);
        assert_eq!(locator.directory().expect("found"), found);
        std::fs::remove_dir_all(root).expect("remove temp root");
    }

    #[test]
    fn file_picker_requests_are_bounded() {
        let request = FilePickerRequest::new("Open").with_extensions(["png", "jpg"]);
        assert!(request.validate().is_ok());
        let request = FilePickerRequest::new("Open").with_extensions(["../png"]);
        assert_eq!(
            request.validate().expect_err("invalid filter").code(),
            PlatformErrorCode::InvalidArgument
        );
    }

    #[test]
    fn notification_validation_does_not_echo_the_body() {
        let request =
            NotificationRequest::new("Title", "x".repeat(MAX_NOTIFICATION_BODY_BYTES + 1));
        let error = request.validate().expect_err("oversized body");
        assert_eq!(error.code(), PlatformErrorCode::InvalidArgument);
        assert!(!error.message().contains('x'));
    }

    #[test]
    fn startup_spec_requires_an_existing_absolute_executable() {
        let root = temporary_directory();
        std::fs::create_dir_all(&root).expect("root");
        let executable = root.join("Covio.exe");
        std::fs::write(&executable, b"").expect("executable placeholder");
        let spec = StartupSpec::new("Covio", &executable);
        assert!(spec.validate().is_ok());
        std::fs::remove_dir_all(root).expect("cleanup");
    }

    #[test]
    fn update_handoff_only_accepts_the_updater_executable() {
        let root = temporary_directory();
        std::fs::create_dir_all(&root).expect("root");
        let updater = root.join("CovioUpdater.exe");
        let other = root.join("other.exe");
        std::fs::write(&updater, b"").expect("updater placeholder");
        std::fs::write(&other, b"").expect("other placeholder");
        assert!(UpdateHandoffRequest::new(&updater).validate().is_ok());
        assert_eq!(
            UpdateHandoffRequest::new(&other)
                .validate()
                .expect_err("other executable")
                .code(),
            PlatformErrorCode::InvalidArgument
        );
        std::fs::remove_dir_all(root).expect("cleanup");
    }
}
