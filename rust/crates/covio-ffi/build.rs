fn main() {
    #[cfg(target_os = "macos")]
    println!("cargo:rustc-cdylib-link-arg=-Wl,-install_name,@rpath/libcovio_ffi.1.dylib");
}
