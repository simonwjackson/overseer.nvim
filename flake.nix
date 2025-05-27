{
  description = "Overseer.nvim development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    
    # Neovim for testing
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, neovim-nightly-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ neovim-nightly-overlay.overlays.default ];
        };

        # Python environment with required packages
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pyparsing
          black
          isort
          mypy
        ]);

        # Lua packages
        luaEnv = pkgs.lua5_1.withPackages (ps: with ps; [
          # Lua tools are installed separately as they need specific versions
        ]);

        # Development shell with all tools
        devShell = pkgs.mkShell {
          name = "overseer-dev";
          
          buildInputs = with pkgs; [
            # Core dependencies
            neovim
            git
            gnumake
            bash
            curl

            # Lua development tools
            lua5_1
            luarocks
            lua51Packages.luacheck
            stylua
            selene

            # Python environment
            pythonEnv

            # Optional task runners for testing templates
            nodejs_20
            nodePackages.npm
            cargo
            rustc
            just
            deno
            elixir
            elixir_ls
            rake
            
            # Utilities
            ripgrep
            fd
            bat
            eza
            jq
            
            # For pushover notifications (from CLAUDE.md)
            curl
          ];

          shellHook = ''
            echo "Overseer.nvim development environment"
            echo "Available tools:"
            echo "  - Neovim: $(nvim --version | head -n1)"
            echo "  - Lua: $(lua -v)"
            echo "  - Python: $(python --version)"
            echo "  - Make: $(make --version | head -n1)"
            echo ""
            echo "Run 'make test' or 'just test' to run tests"
            echo "Run 'make lint' or 'just lint' to run linters"
            echo "Run 'make doc' or 'just doc' to generate documentation"
          '';

          # Set up Lua paths for local development
          LUA_PATH = "./lua/?.lua;./lua/?/init.lua;${pkgs.lua51Packages.plenary-nvim}/share/lua/5.1/?.lua;${pkgs.lua51Packages.plenary-nvim}/share/lua/5.1/?/init.lua;$LUA_PATH";
          LUA_CPATH = "${pkgs.lua51Packages.plenary-nvim}/lib/lua/5.1/?.so;$LUA_CPATH";
        };

        # Package for the plugin itself
        overseerNvim = pkgs.vimUtils.buildVimPlugin {
          pname = "overseer.nvim";
          version = "dev";
          src = ./.;
          
          meta = with pkgs.lib; {
            description = "A task runner and job management plugin for Neovim";
            homepage = "https://github.com/stevearc/overseer.nvim";
            license = licenses.mit;
            maintainers = [];
            platforms = platforms.all;
          };
        };

        # Testing environment with all optional dependencies
        testEnv = pkgs.neovim.override {
          configure = {
            packages.overseer = with pkgs.vimPlugins; {
              start = [
                overseerNvim
                plenary-nvim
                neotest
                nvim-dap
                toggleterm-nvim
                lualine-nvim
                nvim-cmp
              ];
            };
          };
        };

      in
      {
        packages = {
          default = overseerNvim;
          overseer-nvim = overseerNvim;
          test-env = testEnv;
        };

        devShells = {
          default = devShell;
          
          # Minimal shell with just the essentials
          minimal = pkgs.mkShell {
            buildInputs = with pkgs; [
              neovim
              git
              gnumake
              lua5_1
              lua51Packages.luacheck
              stylua
              pythonEnv
            ];
          };

          # CI environment matching GitHub Actions
          ci = pkgs.mkShell {
            buildInputs = with pkgs; [
              neovim
              git
              gnumake
              bash
              lua5_1
              lua51Packages.luacheck
              stylua
              selene
              pythonEnv
            ];
          };
        };

        apps = {
          # Run tests
          test = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "test-overseer" ''
              ${pkgs.bash}/bin/bash ./run_tests.sh "$@"
            '';
          };

          # Run linters
          lint = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "lint-overseer" ''
              ${pkgs.gnumake}/bin/make fastlint
            '';
          };

          # Generate documentation
          doc = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "doc-overseer" ''
              ${pkgs.gnumake}/bin/make doc
            '';
          };
        };

        # GitHub Actions check
        checks = {
          tests = pkgs.stdenv.mkDerivation {
            name = "overseer-tests";
            src = ./.;
            buildInputs = [ devShell.buildInputs ];
            doCheck = true;
            checkPhase = ''
              make test
            '';
          };

          lint = pkgs.stdenv.mkDerivation {
            name = "overseer-lint";
            src = ./.;
            buildInputs = [ devShell.buildInputs ];
            doCheck = true;
            checkPhase = ''
              make fastlint
            '';
          };
        };
      }
    );
}