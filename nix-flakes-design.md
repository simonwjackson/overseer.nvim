# Nix Flakes Support Design Document

## Overview

This document outlines the design for adding Nix flakes support to overseer.nvim. The goal is to provide seamless integration with Nix flakes following overseer's existing architectural patterns.

## Core Integration Strategy

### Template Provider Approach
Following overseer's existing pattern, implement this as a template provider at `lua/overseer/template/nix.lua`, similar to how `make.lua`, `npm.lua`, and `cargo.lua` work.

**Detection Logic:**
- Look for `flake.nix` files in current directory and parent directories
- Optionally support legacy `default.nix` files
- Use the same file discovery patterns as other providers

## Discovery Mechanism

### Two-Tier Approach

**Tier 1: Static Common Commands**
Always provide these basic templates when `flake.nix` is detected:
- `nix develop` - Enter development shell
- `nix build` - Build default package  
- `nix run` - Run default application
- `nix flake check` - Run checks
- `nix flake update` - Update inputs

**Tier 2: Dynamic Discovery**
Optionally use `nix flake show --json` to discover specific targets:
- Individual packages to build (`nix build .#package-name`)
- Individual apps to run (`nix run .#app-name`) 
- Named development shells (`nix develop .#shell-name`)
- Specific checks (`nix flake check .#check-name`)

## Implementation Challenges & Solutions

### Performance Concerns
**Problem:** `nix flake show` can be slow (requires flake evaluation)
**Solution:** 
- Implement aggressive caching with cache invalidation on `flake.nix`/`flake.lock` changes
- Make dynamic discovery opt-in via configuration
- Use overseer's existing template caching mechanism
- Provide timeout configuration for Nix operations

### Parsing Complexity
**Problem:** Nix expressions are complex to parse statically
**Solution:**
- Avoid parsing Nix directly
- Use `nix flake show --json` for structured output
- Fall back to static templates if discovery fails

### Multi-System Support
**Problem:** Flakes can target multiple systems (x86_64-linux, aarch64-darwin, etc.)
**Solution:**
- Default to current system (`nix eval --impure --expr 'builtins.currentSystem'`)
- Allow configuration to specify target system
- Generate templates per discovered system if needed

## Component Integration

### Leverage Existing Components
- **Output parsing:** Use `on_output_quickfix` for Nix build errors
- **Diagnostics:** Use `on_result_diagnostics` for evaluation errors  
- **Timeouts:** Use `timeout` component for slow operations
- **Notifications:** Use `on_complete_notify` for long builds

### Nix-Specific Components
Consider new components for:
- **Environment setup:** Ensure Nix is available and configured
- **Flake context:** Handle flake-relative paths and references
- **Build result tracking:** Parse and display what artifacts were built

## Configuration Design

```lua
-- In overseer config
templates = { "builtin", "nix" },
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

## Template Structure

### Generator Logic
1. **Static phase:** Always provide common commands if `flake.nix` exists
2. **Discovery phase:** If enabled, run `nix flake show --json` to find specific targets
3. **Caching phase:** Cache results keyed by flake.nix modification time
4. **Template creation:** Generate task templates for each discovered target

### Template Naming
- `nix develop` (default shell)
- `nix develop .#shell-name` (named shells)
- `nix build` (default package)
- `nix build .#package-name` (specific packages)
- `nix run .#app-name` (applications)
- `nix flake check` (all checks)

## Error Handling Strategy

### Graceful Degradation
- If `nix` command not found: Skip provider entirely
- If `nix flake show` fails: Fall back to static templates only
- If flake has evaluation errors: Show basic templates but warn user

### Error Categories
1. **Tool availability:** Nix not installed
2. **Flake syntax errors:** Invalid `flake.nix`
3. **Network errors:** Can't fetch inputs
4. **Build errors:** Compilation failures

## Integration Points

### Strategy Compatibility
- **Terminal strategy:** For interactive `nix develop`
- **Jobstart strategy:** For build/run operations
- **Orchestrator strategy:** For complex multi-step Nix workflows

### VS Code Integration
Consider supporting VS Code tasks.json with Nix task types, similar to existing VS Code integration.

## Phased Implementation

### Phase 1: Basic Support
- Static common commands only
- File detection
- Basic template generation

### Phase 2: Dynamic Discovery  
- `nix flake show` integration
- Caching mechanism
- Configuration options

### Phase 3: Advanced Features
- Multi-system support
- Custom components
- VS Code integration
- Legacy Nix support

## Technical Implementation Details

### File Structure
```
lua/overseer/template/nix.lua          -- Main template provider
lua/overseer/component/nix_env.lua     -- Nix environment component (optional)
```

### Discovery Algorithm
```lua
local function discover_flake_targets(flake_path)
  -- 1. Check if nix is available
  -- 2. Run `nix flake show --json` with timeout
  -- 3. Parse JSON output for packages, apps, devShells
  -- 4. Generate template definitions
  -- 5. Cache results with flake.nix mtime as key
end
```

### Caching Strategy
- Cache key: `{flake_path}_{flake_nix_mtime}_{flake_lock_mtime}`
- Cache location: Use overseer's existing template cache
- Invalidation: On flake.nix or flake.lock changes
- TTL: Configurable, default 1 hour for network-dependent operations

### Template Parameters
Common parameters for Nix templates:
- `extra_args`: Additional arguments for Nix commands
- `system`: Target system (optional override)
- `impure`: Whether to allow impure evaluation
- `show_trace`: Enable detailed error traces

## Testing Strategy

### Unit Tests
- Template detection logic
- Discovery parsing
- Cache invalidation
- Error handling

### Integration Tests
- End-to-end template generation
- Multiple flake scenarios
- Performance with large flakes
- Network failure handling

### Test Fixtures
Create test flakes with:
- Multiple packages
- Multiple apps
- Multiple devShells
- Complex dependencies
- Evaluation errors

## Future Considerations

### Advanced Features
- **Flake inputs management:** Templates for updating specific inputs
- **Build profiles:** Support for different build configurations
- **Remote flakes:** Support for GitHub/GitLab flake references
- **Nix-shell compatibility:** Support for legacy shell.nix files
- **Build result inspection:** Show what was built and where

### Performance Optimizations
- **Parallel discovery:** Run multiple `nix flake show` commands concurrently
- **Incremental updates:** Only re-discover changed parts of flakes
- **Background refresh:** Update cache in background without blocking UI

### User Experience
- **Progress indicators:** Show discovery progress for slow flakes
- **Error reporting:** Clear error messages for common Nix issues
- **Documentation:** Integration with overseer's help system

This design leverages overseer's existing architecture while handling Nix's unique characteristics around performance, complexity, and dynamic nature. The phased approach allows for iterative development and user feedback incorporation.