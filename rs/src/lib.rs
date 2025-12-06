//! imp-graph: Interactive force-directed graph visualization for imp flakes.
//!
//! This crate provides a WASM-based graph visualization component that renders
//! dependency graphs with physics-based layout, pan/zoom, and hover effects.

use leptos::prelude::*;
use leptos_meta::*;
use log::{Level, info, warn};
use wasm_bindgen::JsCast;
use web_sys::{HtmlScriptElement, Window};

pub mod components;

pub use components::force_graph::{ForceGraphCanvas, GraphData, GraphLink, GraphNode};

/// Initialize logging and panic hooks for the WASM target.
pub fn init_logging() {
	let _ = console_log::init_with_level(Level::Debug);
	console_error_panic_hook::set_once();
	info!("imp-graph: logging initialized");
}

/// Load graph data from a script element with id="graph-data".
/// Expected format: JSON with { nodes: [...], links: [...] }
fn load_graph_data() -> Option<GraphData> {
	let window: Window = web_sys::window()?;
	let document = window.document()?;
	let element = document.get_element_by_id("graph-data")?;
	let script: HtmlScriptElement = element.dyn_into().ok()?;
	let json_text = script.text().ok()?;

	match serde_json::from_str::<GraphData>(&json_text) {
		Ok(data) => {
			info!(
				"imp-graph: loaded {} nodes, {} links",
				data.nodes.len(),
				data.links.len()
			);
			Some(data)
		}
		Err(e) => {
			warn!("imp-graph: failed to parse graph data: {}", e);
			None
		}
	}
}

/// Main application component.
/// Loads graph data from DOM and renders the force-directed visualization.
#[component]
pub fn App() -> impl IntoView {
	provide_meta_context();

	// Load graph data from the DOM
	let graph_data = load_graph_data().unwrap_or_default();
	let graph_signal = Signal::derive(move || graph_data.clone());

	view! {
		<Html attr:lang="en" attr:dir="ltr" attr:data-theme="dark" />
		<Title text="imp Registry Visualization" />
		<Meta charset="UTF-8" />
		<Meta name="viewport" content="width=device-width, initial-scale=1.0" />

		<div class="fullscreen-graph">
			<ForceGraphCanvas data=graph_signal fullscreen=true />
			<div class="graph-overlay">
				<h1>"imp Registry"</h1>
				<p class="subtitle">"Drag nodes to reposition. Scroll to zoom. Drag background to pan."</p>
			</div>
		</div>
	}
}
