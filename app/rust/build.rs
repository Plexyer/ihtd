fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        // APK ZIP alignment does not fix ELF PT_LOAD alignment. Keep this in
        // the crate so local/native-assets/CI builds all link the same library.
        println!("cargo:rustc-link-arg-cdylib=-Wl,-z,max-page-size=16384");
    }
}
