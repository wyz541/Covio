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
        .any(|argument| argument == "--headless-smoke")
    {
        match covio_windows::run_headless_smoke() {
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
