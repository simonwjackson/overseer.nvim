# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Overseer.nvim is a task runner and job management plugin for Neovim. It provides a comprehensive framework for running, monitoring, and managing tasks with an entity-component-system (ECS) architecture.

## Core Architecture

### Tasks, Components, and Strategies
- **Tasks** (`lua/overseer/task.lua`): Central entities that represent commands to run. Tasks have a status lifecycle (PENDING → RUNNING → SUCCESS/FAILURE/CANCELED → DISPOSED)
- **Components** (`lua/overseer/component/`): Modular functionality attached to tasks using ECS pattern. Components handle events like `on_start`, `on_output`, `on_complete`, etc.
- **Strategies** (`lua/overseer/strategy/`): Define how tasks are executed (terminal, jobstart, toggleterm, orchestrator, etc.)
- **Templates** (`lua/overseer/template/`): Blueprints for creating tasks, providing reusable task definitions with parameters

### Key Modules
- `lua/overseer/init.lua`: Main entry point with lazy loading and command setup
- `lua/overseer/config.lua`: Configuration management with deep merging
- `lua/overseer/task_list/`: Task list UI and management
- `lua/overseer/commands.lua`: Implementation of user commands like `:OverseerRun`
- `lua/overseer/parser/`: Output parsing system for extracting diagnostics and results

## Development Commands

### Testing
```bash
# Run all tests
./run_tests.sh

# Run specific test files
./run_tests.sh tests/parser_spec.lua

# Use justfile for testing (alternative)
just test
just test tests/parser_spec.lua
```

### Linting and Formatting
```bash
# Run all linting and formatting checks
make fastlint

# Individual tools
luacheck lua tests --formatter plain
stylua --check lua tests

# Format code
stylua lua tests

# Full lint with type checking (requires external dependencies)
make lint
```

### Documentation
```bash
# Generate documentation
make doc

# Using justfile alternative
just doc
```

### Build Tasks
```bash
# Run all (documentation, linting, tests)
make all

# Clean build artifacts
make clean
```

## Template System

Templates are the primary way users define tasks. They can be:
1. **File-based templates**: In `lua/overseer/template/` directory (builtin providers like make, npm, cargo, just, nix)
2. **Provider-based templates**: Dynamic template generation based on project state
3. **User-defined templates**: Custom templates via `overseer.register_template()`

Template providers in `lua/overseer/template/` automatically scan for project files (Makefile, package.json, Cargo.toml, justfile, flake.nix, etc.) and generate appropriate task templates.

### Nix Flakes Support

The Nix template provider (`lua/overseer/template/nix.lua`) provides integration with Nix flakes:
- **Detection**: Searches for `flake.nix` files using upward directory traversal
- **Static templates**: Provides common Nix commands (develop, build, run, flake check, flake update)
- **Future phases**: Will include dynamic discovery via `nix flake show --json`

### Just Template with Submodules Support

The just template (`lua/overseer/template/just.lua`) supports:
- Regular justfile recipes
- Submodule recipes with `::` namespace syntax (e.g., `frontend::build`, `backend::api::deploy`)
- Automatic discovery of nested submodules through JSON dump format
- Priority ordering (first recipe gets priority 55, root recipes get 60, submodule recipes get 65)

## Component System

Components use an event-driven architecture:
- `on_init`: Component initialization
- `on_start`: When task starts
- `on_output`/`on_output_lines`: Process task output
- `on_result`: Handle task results
- `on_complete`: Task completion handling
- `on_dispose`: Cleanup

Common component patterns:
- Output processing: `on_output_*` components
- Result handling: `on_result_*` components  
- Lifecycle management: `on_complete_*` components

## Testing Architecture

- Uses Plenary.nvim for testing framework
- Test files in `tests/` directory with `*_spec.lua` pattern
- `tests/minimal_init.lua` provides minimal test environment
- Tests are isolated with custom XDG directories in `.testenv/`

## VS Code Integration

Overseer has extensive VS Code tasks.json support in `lua/overseer/template/vscode/`:
- `provider/`: Different task type providers (npm, shell, typescript, etc.)
- `problem_matcher.lua`: Converts VS Code problem matchers to parsers
- `variables.lua`: VS Code variable interpolation

## Configuration

The config system supports:
- Component aliases for reusable component bundles
- Task list appearance and key bindings
- Form/editor UI customization
- Logging configuration
- Template loading and caching

## Nix Flakes Support

Phase 2 implementation (completed) includes:

### Dynamic Discovery
- Uses `nix flake show --json` to discover specific packages, apps, devShells, and checks
- Generates individual templates for each discovered target (e.g., `nix build .#mypackage`)
- Falls back gracefully to static templates if discovery fails

### Configuration Options
```lua
-- In overseer setup
nix = {
  -- Enable dynamic discovery via `nix flake show`
  dynamic_discovery = true,
  -- Timeout for nix operations (ms)
  timeout = 30000,
  -- Target system (nil = auto-detect)
  system = nil,
  -- Include legacy default.nix support
  legacy_support = true,
  -- Cache discovery results
  cache_discovery = true,
}
```

### Caching Mechanism
- Cache keys include `flake.nix` and `flake.lock` modification times
- Uses overseer's existing template cache infrastructure
- Automatic cache invalidation on file changes
- Configurable timeout and cache thresholds

### Enhanced Template Parameters
- `extra_args`: Additional Nix command arguments
- `system`: Target system override
- `impure`: Allow impure evaluation
- `show_trace`: Enable detailed error traces

## Key Files for Development

- `lua/overseer/constants.lua`: Status codes and other constants
- `lua/overseer/util.lua`: Common utility functions
- `lua/overseer/log.lua`: Logging system
- `lua/overseer/files.lua`: File system utilities
- `lua/overseer/shell.lua`: Shell command utilities
- `lua/overseer/template/nix.lua`: Nix flakes template provider with dynamic discovery