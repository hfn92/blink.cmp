{
  description = "Set of simple, performant neovim plugins";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems =
        [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { self, config, self', inputs', pkgs, system, lib, ... }: {
        # use fenix overlay
        _module.args.pkgs = import nixpkgs {
          inherit system;
          overlays = [ inputs.fenix.overlays.default ];
        };

        # define the packages provided by this flake
        packages = let
          fs = lib.fileset;
          # nix source files (*.nix)
          nixFs = fs.fileFilter (file: file.hasExt == "nix") ./.;
          # rust source files
          rustFs = fs.unions [
            # Cargo.*
            (fs.fileFilter (file: lib.hasPrefix "Cargo" file.name) ./.)
            # *.rs
            (fs.fileFilter (file: file.hasExt "rs") ./.)
            # additional files
            ./.cargo
            ./rust-toolchain.toml
          ];
          # nvim source files
          # all that are not nix, nor rust
          nvimFs = fs.difference ./. (fs.union nixFs rustFs);
          version = "0.9.2";
        in {
          blink-fuzzy-lib = let
            inherit (inputs'.fenix.packages.minimal) toolchain;
            rustPlatform = pkgs.makeRustPlatform {
              cargo = toolchain;
              rustc = toolchain;
            };
          in rustPlatform.buildRustPackage {
            pname = "blink-fuzzy-lib";
            inherit version;
            src = fs.toSource {
              root = ./.;
              fileset = rustFs;
            };
            cargoLock = {
              lockFile = ./Cargo.lock;
              allowBuiltinFetchGit = true;
            };

            nativeBuildInputs = with pkgs; [ git ];
          };

          blink-cmp = pkgs.vimUtils.buildVimPlugin {
            pname = "blink-cmp";
            inherit version;
            src = fs.toSource {
              root = ./.;
              fileset = nvimFs;
            };
            preInstall = ''
              mkdir -p target/release
              ln -s ${self'.packages.blink-fuzzy-lib}/lib/libblink_cmp_fuzzy.* target/release/
            '';
          };

          default = self'.packages.blink-cmp;
        };

        # builds the native module of the plugin
        apps.build-plugin = {
          type = "app";
          program = let
            buildScript = pkgs.writeShellApplication {
              name = "build-plugin";
              runtimeInputs = with pkgs;
                [
                  fenix.minimal.toolchain
                ]
                # use the native gcc on macos, see #652
                ++ lib.optionals (!pkgs.stdenv.isDarwin) [ gcc ];
              text = ''
                cargo build --release
              '';
            };
          in (lib.getExe buildScript);
        };

        # define the default dev environment
        devShells.default = pkgs.mkShell {
          name = "blink";
          inputsFrom = [
            self'.packages.blink-fuzzy-lib
            self'.packages.blink-cmp
            self'.apps.build-plugin
          ];
          packages = with pkgs; [ rust-analyzer-nightly ];
        };

        formatter = pkgs.nixfmt-classic;
      };
    };
}
