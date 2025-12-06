# imp.graph

Interactive force-directed graph visualization for flake dependencies.

## Overview

imp.graph provides a WASM-based visualization component for exploring flake dependency graphs. It renders interactive force-directed graphs with:

- Physics-based node positioning
- Pan, zoom, and node dragging
- Smooth highlight transitions on hover
- Cluster-based coloring for different module types
- Node merging for cleaner visualization

## Usage

### As a Nix Library

```nix
{
  inputs.imp-graph.url = "github:imp-nix/imp.graph";

  outputs = { imp-graph, ... }:
    let
      visualize = imp-graph.lib;

      # Your graph from imp.analyze
      graph = {
        nodes = [ ... ];
        edges = [ ... ];
      };

      # Generate HTML with embedded WASM visualization
      html = visualize.toHtml {
        inherit graph;
        wasmDistPath = imp-graph.packages.x86_64-linux.default;
      };
    in
    { ... };
}
```

### Available Functions

- `toJson graph` - Convert graph to JSON with full paths
- `toJsonMinimal graph` - Convert graph to JSON without paths
- `toHtml { graph, wasmDistPath }` - Generate interactive HTML visualization
- `toHtmlWith { graph, wasmDistPath, colors }` - HTML with custom cluster colors
- `toWasmData { graph, colors? }` - Convert graph to WASM component format
- `mkVisualizeScript { pkgs, graph, wasmDistPath, ... }` - Create CLI script

### Cluster Colors

Default colors are provided for common clusters:

```nix
{
  "modules.home" = "#1976d2";
  "modules.nixos" = "#7b1fa2";
  "outputs.nixosConfigurations" = "#e65100";
  "outputs.homeConfigurations" = "#2e7d32";
  # ...
}
```

Override with custom colors:

```nix
visualize.toHtmlWith {
  inherit graph wasmDistPath;
  colors = {
    "modules.custom" = "#ff5722";
  };
}
```

## Development

```bash
# Enter dev shell
nix develop

# Run Trunk dev server (in rs/)
cd rs && trunk serve

# Run Nix tests
nix flake check

# Build WASM package
nix build
```

## License

MIT
