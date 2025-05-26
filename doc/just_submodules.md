# Just Submodules Support

This document describes the just submodules support added to overseer.nvim.

## Overview

The just template in overseer.nvim now supports just submodules, which allows organizing recipes into hierarchical modules within a justfile.

## Features

- **Automatic Discovery**: Submodule recipes are automatically discovered through the JSON dump format
- **Namespace Syntax**: Submodule recipes appear with `::` namespace syntax (e.g., `frontend::build`, `backend::api::deploy`)
- **Deep Nesting**: Supports deeply nested submodules (e.g., `backend::api::v1::deploy`)
- **Priority Ordering**: 
  - First recipe: priority 55
  - Root recipes: priority 60  
  - Submodule recipes: priority 65
- **Parameter Support**: Submodule recipes fully support parameters like regular recipes
- **Private Recipe Filtering**: Private recipes in submodules are properly filtered out

## Example

Given a justfile with submodules:

```justfile
# Root level recipes
test:
  cargo test

build:
  cargo build

# Submodules
mod frontend
mod backend
```

And submodule files:

**frontend.just**:
```justfile
dev:
  npm run dev

build:
  npm run build
```

**backend.just**:
```justfile
serve:
  cargo run

deploy:
  ./deploy.sh
```

The overseer template will generate tasks:
- `just test` (priority 55 if first recipe)
- `just build` (priority 60)  
- `just frontend::dev` (priority 65)
- `just frontend::build` (priority 65)
- `just backend::serve` (priority 65)
- `just backend::deploy` (priority 65)

## Implementation

The implementation works by:

1. Using `just --unstable --dump --dump-format json` to get the complete project structure
2. Recursively processing the `modules` field in the JSON output
3. Building task names with `::` namespace separators
4. Preserving all parameter and metadata handling for submodule recipes

## Compatibility

This feature requires:
- `just` command-line tool with submodule support
- The `--unstable` flag for JSON dump functionality

The implementation is backward-compatible with justfiles that don't use submodules.