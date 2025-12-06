{
  description = "Interactive force-directed graph visualization for imp flake dependencies";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
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
          rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
            targets = [ "wasm32-unknown-unknown" ];
            extensions = [ "rust-src" ];
          };
        in
        {
          # The WASM app built via Trunk
          default = pkgs.stdenv.mkDerivation {
            pname = "imp-graph";
            version = "0.1.0";
            src = ./rs;

            nativeBuildInputs = [
              rustToolchain
              pkgs.trunk
              pkgs.wasm-bindgen-cli_0_2_104
              pkgs.dart-sass
              pkgs.binaryen # for wasm-opt
            ];

            buildPhase = ''
              export HOME=$TMPDIR
              trunk build --release
            '';

            installPhase = ''
              cp -r dist $out
            '';
          };

          # The HTML template with WASM embedded (as a derivation)
          html-template = pkgs.runCommand "imp-graph-template" { } ''
            mkdir -p $out
            cp -r ${self.packages.${system}.default}/* $out/
          '';
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
              pkgs.wasm-bindgen-cli_0_2_104
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

          # Nix evaluation test (simpler than nix-unit in sandbox)
          nix-eval = pkgs.runCommand "nix-eval-test" { } ''
            # Just verify the tests can be evaluated
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
