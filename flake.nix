{
  description = "Interactive force-directed graph visualization for imp flake dependencies";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      crane,
      nix-unit,
      treefmt-nix,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

      # Import the Nix visualization library
      visualizeLib = import ./nix { lib = nixpkgs.lib; };
    in
    {
      # Export visualization functions
      lib = visualizeLib;

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;

          # Rust toolchain with WASM target
          rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
            targets = [ "wasm32-unknown-unknown" ];
            extensions = [ "rust-src" ];
          };

          # Crane library for building Rust
          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          # Common args for crane builds
          commonArgs = {
            src = craneLib.cleanCargoSource ./rs;
            strictDeps = true;

            CARGO_BUILD_TARGET = "wasm32-unknown-unknown";

            # Needed for wasm builds
            doCheck = false;
          };

          # Build cargo dependencies separately for caching
          cargoArtifacts = craneLib.buildDepsOnly (
            commonArgs
            // {
              # Dummy src for deps-only build
              pname = "imp-graph-deps";
            }
          );

          # Build the WASM binary
          wasmBuild = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              pname = "imp-graph";
              version = "0.1.0";
            }
          );
        in
        {
          # The WASM app with HTML/JS wrapper
          default = pkgs.stdenv.mkDerivation {
            pname = "imp-graph";
            version = "0.1.0";
            src = ./rs;

            nativeBuildInputs = [
              pkgs.wasm-bindgen-cli_0_2_100
              pkgs.binaryen
              pkgs.dart-sass
            ];

            buildPhase = ''
              # Generate JS bindings
              wasm-bindgen \
                ${wasmBuild}/bin/imp-graph.wasm \
                --out-dir pkg \
                --target web \
                --no-typescript

              # Optimize WASM
              wasm-opt -Oz pkg/imp-graph_bg.wasm -o pkg/imp-graph_bg.wasm

              # Compile SCSS
              sass public/styles.scss:styles.css --style=compressed --no-source-map

              # Create output directory
              mkdir -p dist
            '';

            installPhase = ''
              mkdir -p $out

              # Copy index.html with inline modifications for standalone use
              cat > $out/index.html << 'EOF'
              <!DOCTYPE html>
              <html lang="en">
              <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>imp - Dependency Graph</title>
                  <style>
              EOF
              cat styles.css >> $out/index.html
              cat >> $out/index.html << 'EOF'
                  </style>
                  <link data-trunk rel="rust" data-wasm-opt="z" />
              </head>
              <body>
                  <script type="module">
                      import init, * as bindings from './imp-graph.js';
                      window.wasmBindings = bindings;
                      // Initial graph data - will be replaced by Nix
                      const graphData = {"nodes":[],"links":[]};
                      init().then(() => {
                          if (window.wasmBindings.hydrate) {
                              window.wasmBindings.hydrate();
                          }
                          // Make graph data available globally
                          window.graphData = graphData;
                      });
                  </script>
              </body>
              </html>
              EOF

              # Copy WASM and JS files
              cp pkg/imp-graph_bg.wasm $out/
              cp pkg/imp-graph.js $out/

              # Copy favicon
              cp public/favicon.ico $out/ 2>/dev/null || true
            '';
          };

          # Just the WASM binary (for reference)
          wasm = wasmBuild;

          # Cargo artifacts (for caching)
          deps = cargoArtifacts;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            programs.rustfmt.enable = true;
          };
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              (pkgs.rust-bin.nightly.latest.default.override {
                targets = [ "wasm32-unknown-unknown" ];
                extensions = [ "rust-src" ];
              })
              pkgs.trunk
              pkgs.wasm-bindgen-cli_0_2_100
              pkgs.dart-sass
              pkgs.cargo-sort
              treefmtEval.config.build.wrapper
              nix-unit.packages.${system}.default
            ];
          };
        }
      );

      formatter = forAllSystems (
        system:
        (treefmt-nix.lib.evalModule (pkgsFor system) {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }).config.build.wrapper
      );

      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          # Build check
          build = self.packages.${system}.default;

          # Nix evaluation test
          nix-eval = pkgs.runCommand "nix-eval-test" { } ''
            ${pkgs.nix}/bin/nix eval --json --expr '
              let
                lib = import ${nixpkgs}/lib;
                tests = import ${self}/tests { inherit lib; };
              in
              builtins.attrNames tests
            ' > $out
          '';
        }
      );

      # Export tests for nix-unit
      tests = import ./tests { lib = nixpkgs.lib; };
    };
}
