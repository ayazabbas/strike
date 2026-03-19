//! Event subscription and historical scanning.
//!
//! - [`subscribe`] — live WSS event streams with auto-reconnect
//! - [`scan`] — historical event scanning via chunked `getLogs`

pub mod scan;
pub mod subscribe;
