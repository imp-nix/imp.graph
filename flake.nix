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

      visualizeLib = import ./nix { lib = nixpkgs.lib; };
    in
    {
      lib = visualizeLib;

      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;

          rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
            targets = [ "wasm32-unknown-unknown" ];
            extensions = [ "rust-src" ];
          };

          craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

          commonArgs = {
            src = craneLib.cleanCargoSource ./rs;
            strictDeps = true;
            CARGO_BUILD_TARGET = "wasm32-unknown-unknown";
            doCheck = false;
          };

          cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { pname = "imp-graph-deps"; });

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
          # Self-contained HTML with inlined WASM - works with file:// URLs
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
              wasm-bindgen \
                ${wasmBuild}/bin/imp-graph.wasm \
                --out-dir pkg \
                --target web \
                --no-typescript

              wasm-opt -Oz pkg/imp-graph_bg.wasm -o pkg/imp-graph_bg.wasm
              sass public/styles.scss:styles.css --style=compressed --no-source-map
            '';

            installPhase = ''
                            mkdir -p $out

                            WASM_BASE64=$(base64 -w0 pkg/imp-graph_bg.wasm)

                            # Convert ES module to inline script
                            sed -e 's/^export { initSync };$//' \
                                -e 's/^export default __wbg_init;$//' \
                                -e 's/^export class /class /' \
                                -e "s/import\.meta\.url/'inline'/" \
                                pkg/imp-graph.js > pkg/imp-graph-inline.js

                            cat > $out/index.html << 'HTMLHEAD'
              <!DOCTYPE html>
              <html lang="en">
              <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>imp - Dependency Graph</title>
                  <style>
              HTMLHEAD
                            cat styles.css >> $out/index.html
                            cat >> $out/index.html << 'HTMLMID'
                  </style>
              </head>
              <body>
                  <script id="graph-data" type="application/json">{"nodes":[],"links":[]}</script>
                  <script>
                  (function() {
              HTMLMID
                            cat pkg/imp-graph-inline.js >> $out/index.html
                            cat >> $out/index.html << HTMLTAIL
                      var wasmBytes = Uint8Array.from(atob("$WASM_BASE64"), function(c) { return c.charCodeAt(0); });
                      initSync(wasmBytes);
                  })();
                  </script>
              </body>
              </html>
              HTMLTAIL
            '';
          };

          wasm = wasmBuild;
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
          build = self.packages.${system}.default;

          # Tests are evaluated at build time - if evaluation fails, the check fails
          nix-eval =
            let
              lib = nixpkgs.lib;
              tests = import ./tests { inherit lib; };
              testNames = builtins.attrNames tests;
            in
            pkgs.runCommand "nix-eval-test" { } ''
              echo "Tests evaluated successfully: ${builtins.concatStringsSep ", " testNames}"
              touch $out
            '';
        }
      );

      tests = import ./tests { lib = nixpkgs.lib; };
    };
}
