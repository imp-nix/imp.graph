//! Client entrypoint for the CSR build.

// Bin target reuses lib deps, silence noisy lint.
#![allow(unused_crate_dependencies)]

use imp_graph::{init_logging, App};
use leptos::prelude::*;

fn main() {
	init_logging();

	mount_to_body(|| {
		view! { <App /> }
	})
}
