{
  description = "Set of simple, performant Neovim plugins";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    devenv.url = "github:cachix/devenv";
    flake-parts.url = "github:hercules-ci/flake-parts";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
  };

  nixConfig = {
    extra-trusted-public-keys =
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = inputs@{ flake-parts, nixpkgs, fenix, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.devenv.flakeModule ];
    systems = [
      "x86_64-linux"
      "i686-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "aarch64-darwin"
    ];

    perSystem = { config, self', inputs', pkgs, system, lib, ... }: {
      # define the packages provided by this flake
      packages = let
        inherit (fenix.packages.${system}.minimal) toolchain;

        rustPlatform = pkgs.makeRustPlatform {
          cargo = toolchain;
          rustc = toolchain;
        };

        src = ./.;
        version = "2024-08-02";

        # Build the Rust library used by the Vim plugin
        blink-fuzzy-lib = rustPlatform.buildRustPackage {
          pname = "blink-fuzzy-lib";
          inherit src version;
          cargoLock = {
            lockFile = ./Cargo.lock;
            outputHashes = {
              "c-marshalling-0.2.0" = "sha256-eL6nkZOtuLLQ0r31X7uroUUDYZsWOJ9KNXl4NCVNRuw=";
              "frizbee-0.1.0" = "sha256-9L3ZS7GMvLEqOBjC/VW2jHEZge/s6jRN7ok647Frl/M=";
            };
          };

          cargoBuildOptions = [ "--release" "--lib" "--features" "fuzzy" ];

          installPhase = ''
            # Copy the built library to the output path
            mkdir -p $out/lib
            cp target/release/libblink_cmp_fuzzy.so $out/lib/
          '';
        };

      in {
        blink-cmp = pkgs.vimUtils.buildVimPlugin {
          pname = "blink-cmp";
          inherit src version;

          buildInputs = [ blink-fuzzy-lib ];

          # Ensure the plugin uses the locally built library
          postInstall = ''
            # Copy the built .so file to Neovim's runtime path
            localLibDir=$out/lib
            mkdir -p $localLibDir
            cp ${blink-fuzzy-lib}/lib/libblink_cmp_fuzzy.so $localLibDir/

            # Write Neovim configuration to use the local .so file
            echo "let g:fuzzy_prebuilt_binary_path='$localLibDir/libblink_cmp_fuzzy.so'" >> $out/plugin/blink-cmp.vim
            echo "let g:fuzzy_library_path='$localLibDir'" >> $out/plugin/blink-cmp.vim
          '';

          vimFiles.plugin = "plugin/blink-cmp.vim";

          meta = {
            description = "Performant, batteries-included completion plugin for Neovim";
            homepage = "https://github.com/saghen/blink.cmp";
            license = lib.licenses.mit;
            maintainers = with lib.maintainers; [ redxtech ];
          };
        };

        default = self'.packages.blink-cmp;
      };

      # define the default dev environment
      devenv.shells.default = {
        name = "blink";

        # Set environment to use the locally built .so file during runtime
        environment = {
          LD_LIBRARY_PATH = "${self'.packages.blink-fuzzy-lib}/lib:$LD_LIBRARY_PATH";
          FUZZY_PREBUILT_BINARY_PATH = "${self'.packages.blink-fuzzy-lib}/lib/libblink_cmp_fuzzy.so";
        };

        languages.rust = {
          enable = true;
          channel = "nightly";
        };
      };
    };
  };
}

