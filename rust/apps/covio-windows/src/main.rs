#[cfg(target_os = "windows")]
mod windows_app;

fn main() {
    if std::env::args().any(|argument| argument == "--headless-smoke") {
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
