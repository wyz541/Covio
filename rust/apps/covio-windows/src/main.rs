#[cfg(target_os = "windows")]
mod top_edge;
#[cfg(target_os = "windows")]
mod visuals;
#[cfg(target_os = "windows")]
mod windows_app;

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    if let Some(index) = arguments
        .iter()
        .position(|argument| argument == "--capability-smoke-helper")
    {
        let Some(marker) = arguments.get(index + 1) else {
            eprintln!("Capability smoke helper requires a marker path.");
            std::process::exit(1);
        };
        if let Err(error) = std::fs::write(marker, b"started") {
            eprintln!("Capability smoke helper cannot write its marker: {error}");
            std::process::exit(1);
        }
        return;
    }

    if arguments
        .iter()
        .any(|argument| argument == "--capability-smoke")
    {
        match covio_windows::run_capability_smoke() {
            Ok(report) => {
                match serde_json::to_string_pretty(&report) {
                    Ok(output) => println!("{output}"),
                    Err(error) => {
                        eprintln!("Cannot encode capability smoke report: {error}");
                        std::process::exit(1);
                    }
                }
                let passed = report.app_data_available
                    && report.atomic_write
                    && report.credential_manager
                    && report.clipboard
                    && report.startup
                    && report.screenshot_directory
                    && report.file_picker
                    && report.notification
                    && report.update_handoff
                    && report.power_unavailable;
                if !passed {
                    eprintln!("Windows capability smoke failed.");
                    std::process::exit(1);
                }
            }
            Err(error) => {
                eprintln!("Windows capability smoke failed: {error}");
                std::process::exit(1);
            }
        }
        return;
    }

    if arguments
        .iter()
        .any(|argument| argument == "--crash-recovery-smoke")
    {
        let root = match data_directory_from_arguments(&arguments) {
            Ok(root) => root,
            Err(error) => {
                eprintln!("Crash recovery smoke failed: {error}");
                std::process::exit(1);
            }
        };
        if let Err(error) = covio_windows::run_headless_smoke_at(&root) {
            eprintln!("Crash recovery smoke setup failed: {error}");
            std::process::exit(1);
        }
        std::process::exit(23);
    }

    if arguments
        .iter()
        .any(|argument| argument == "--headless-smoke")
    {
        let result = if arguments.iter().any(|argument| argument == "--data-dir") {
            data_directory_from_arguments(&arguments)
                .and_then(|root| covio_windows::run_headless_smoke_at(&root))
        } else {
            covio_windows::run_headless_smoke()
        };
        match result {
            Ok(report) => {
                match serde_json::to_string_pretty(&report) {
                    Ok(output) => println!("{output}"),
                    Err(error) => {
                        eprintln!("Cannot encode headless smoke report: {error}");
                        std::process::exit(1);
                    }
                }
                if !report.restart_preserved || !report.shutdown_closed_submissions {
                    eprintln!("Headless core restart smoke failed.");
                    std::process::exit(1);
                }
            }
            Err(error) => {
                eprintln!("Headless core smoke failed: {error}");
                std::process::exit(1);
            }
        }
        return;
    }

    #[cfg(target_os = "windows")]
    {
        if let Err(error) = windows_app::run() {
            eprintln!("Covio Windows host failed: {error}");
            std::process::exit(1);
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        eprintln!("covio-windows must run on Windows 11.");
        std::process::exit(1);
    }
}

fn data_directory_from_arguments(arguments: &[String]) -> Result<std::path::PathBuf, String> {
    if let Some(index) = arguments
        .iter()
        .position(|argument| argument == "--data-dir")
    {
        let path = arguments
            .get(index + 1)
            .ok_or_else(|| "--data-dir requires a path".to_owned())?;
        return Ok(std::path::PathBuf::from(path));
    }
    Err("missing data directory".to_owned())
}
