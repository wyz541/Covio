//! JNI bridge for the Windows Compose host.
//!
//! The crate contains no UI or platform policy. It validates bridge envelopes,
//! runs Rust commands, and returns bounded control messages to Kotlin.

#![allow(unsafe_code)]
#![deny(unsafe_op_in_unsafe_fn)]

mod commands;
mod jni_api;
mod session;

pub use commands::{CommandContext, CommandError, ComposeConfig, ComposeCore};
pub use session::{JniSession, SessionError};
