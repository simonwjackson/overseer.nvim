local constants = require("overseer.constants")
local config = require("overseer.config")
local json = require("overseer.json")
local log = require("overseer.log")
local overseer = require("overseer")
local TAG = constants.TAG

-- Default configuration for Nix support
local nix_config = {
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

-- Merge user config if available
if config.nix then
  nix_config = vim.tbl_deep_extend("force", nix_config, config.nix)
end

---@type overseer.TemplateFileDefinition
local tmpl = {
  priority = 60,
  params = {
    args = { optional = true, type = "list", delimiter = " " },
    cwd = { optional = true },
    extra_args = { optional = true, type = "list", delimiter = " ", desc = "Additional arguments for Nix commands" },
    system = { optional = true, type = "string", desc = "Target system (e.g., x86_64-linux)" },
    impure = { optional = true, type = "boolean", desc = "Allow impure evaluation" },
    show_trace = { optional = true, type = "boolean", desc = "Enable detailed error traces" },
  },
  builder = function(params)
    local args = vim.deepcopy(params.args or {})
    
    -- Add extra arguments
    if params.extra_args then
      vim.list_extend(args, params.extra_args)
    end
    
    -- Add system specification
    if params.system then
      vim.list_extend(args, { "--system", params.system })
    end
    
    -- Add impure flag
    if params.impure then
      table.insert(args, "--impure")
    end
    
    -- Add show-trace flag
    if params.show_trace then
      table.insert(args, "--show-trace")
    end
    
    return {
      cmd = { "nix" },
      args = args,
      cwd = params.cwd,
      components = { "default", { "timeout", timeout = nix_config.timeout } },
    }
  end,
}

---@param opts overseer.SearchParams
---@return string|nil
local function get_flake_file(opts)
  return vim.fs.find("flake.nix", { upward = true, type = "file", path = opts.dir })[1]
end

---@param opts overseer.SearchParams
---@return string|nil
local function get_legacy_nix_file(opts)
  if not nix_config.legacy_support then
    return nil
  end
  return vim.fs.find("default.nix", { upward = true, type = "file", path = opts.dir })[1]
end

---Get the current system for Nix operations
---@return string|nil
local function get_current_system()
  if nix_config.system then
    return nix_config.system
  end
  
  -- Try to get current system from Nix
  local handle = io.popen("nix eval --impure --expr 'builtins.currentSystem' 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result and result ~= "" then
      return result:gsub('"', ""):gsub("\n", "")
    end
  end
  
  return nil
end

---Parse `nix flake show --json` output to discover targets
---@param flake_path string
---@return table|nil
local function discover_flake_targets(flake_path)
  if not nix_config.dynamic_discovery then
    return nil
  end
  
  local cwd = vim.fs.dirname(flake_path)
  local system = get_current_system()
  
  -- Build the command
  local cmd = { "nix", "flake", "show", "--json" }
  if system then
    vim.list_extend(cmd, { "--system", system })
  end
  
  log:debug("Running nix flake show for %s", flake_path)
  
  -- Use vim.system for synchronous execution with timeout
  local result = vim.system(cmd, {
    cwd = cwd,
    timeout = nix_config.timeout,
  }):wait()
  
  if result.code ~= 0 then
    log:warn("nix flake show failed with exit code %d: %s", result.code, result.stderr or "")
    return nil
  end
  
  local output = result.stdout
  if not output or output == "" then
    log:debug("nix flake show returned empty output")
    return nil
  end
  
  -- Parse JSON output
  local ok, parsed = pcall(json.decode, output)
  if not ok then
    log:warn("Failed to parse nix flake show JSON output: %s", parsed)
    return nil
  end
  
  return parsed
end

---Generate templates for specific flake targets
---@param flake_data table
---@param cwd string
---@param system string|nil
---@return table[]
local function generate_dynamic_templates(flake_data, cwd, system)
  local templates = {}
  system = system or get_current_system()
  
  if not flake_data or not system then
    return templates
  end
  
  -- Generate templates for packages
  if flake_data.packages and flake_data.packages[system] then
    for package_name, _ in pairs(flake_data.packages[system]) do
      if package_name ~= "default" then  -- Skip default, it's already covered
        table.insert(templates, {
          name = string.format("nix build .#%s", package_name),
          tags = { TAG.BUILD },
          desc = string.format("Build package '%s'", package_name),
          args = { "build", string.format(".#%s", package_name) },
        })
      end
    end
  end
  
  -- Generate templates for apps
  if flake_data.apps and flake_data.apps[system] then
    for app_name, _ in pairs(flake_data.apps[system]) do
      if app_name ~= "default" then  -- Skip default, it's already covered
        table.insert(templates, {
          name = string.format("nix run .#%s", app_name),
          tags = { TAG.RUN },
          desc = string.format("Run application '%s'", app_name),
          args = { "run", string.format(".#%s", app_name) },
        })
      end
    end
  end
  
  -- Generate templates for devShells
  if flake_data.devShells and flake_data.devShells[system] then
    for shell_name, _ in pairs(flake_data.devShells[system]) do
      if shell_name ~= "default" then  -- Skip default, it's already covered
        table.insert(templates, {
          name = string.format("nix develop .#%s", shell_name),
          tags = { TAG.BUILD },
          desc = string.format("Enter development shell '%s'", shell_name),
          args = { "develop", string.format(".#%s", shell_name) },
        })
      end
    end
  end
  
  -- Generate templates for checks
  if flake_data.checks and flake_data.checks[system] then
    for check_name, _ in pairs(flake_data.checks[system]) do
      table.insert(templates, {
        name = string.format("nix build .#checks.%s.%s", system, check_name),
        tags = { TAG.TEST },
        desc = string.format("Run check '%s'", check_name),
        args = { "build", string.format(".#checks.%s.%s", system, check_name) },
      })
    end
  end
  
  return templates
end

---@type overseer.TemplateFileProvider
local provider = {
  cache_key = function(opts)
    local flake_file = get_flake_file(opts)
    if not flake_file then
      local legacy_file = get_legacy_nix_file(opts)
      if legacy_file then
        return legacy_file
      end
      return nil
    end
    
    if not nix_config.cache_discovery then
      return nil
    end
    
    -- Create cache key based on flake.nix and flake.lock modification times
    local flake_stat = vim.loop.fs_stat(flake_file)
    local flake_lock = vim.fs.dirname(flake_file) .. "/flake.lock"
    local lock_stat = vim.loop.fs_stat(flake_lock)
    
    local cache_key = flake_file
    if flake_stat then
      cache_key = cache_key .. "_" .. flake_stat.mtime.sec
    end
    if lock_stat then
      cache_key = cache_key .. "_" .. lock_stat.mtime.sec
    end
    
    return cache_key
  end,
  condition = {
    callback = function(opts)
      if vim.fn.executable("nix") == 0 then
        return false, 'Command "nix" not found'
      end
      local flake_file = get_flake_file(opts)
      local legacy_file = get_legacy_nix_file(opts)
      if not flake_file and not legacy_file then
        return false, "No flake.nix or default.nix file found"
      end
      return true
    end,
  },
  generator = function(opts, cb)
    local flake_file = get_flake_file(opts)
    local legacy_file = get_legacy_nix_file(opts)
    local nix_file = flake_file or legacy_file
    
    if not nix_file then
      cb({})
      return
    end
    
    local cwd = vim.fs.dirname(nix_file)
    local ret = {}
    
    -- Phase 1: Static common commands
    local commands = {}
    
    if flake_file then
      -- Flake-specific commands
      commands = {
        { 
          args = { "develop" }, 
          name = "nix develop", 
          tags = { TAG.BUILD },
          desc = "Enter development shell"
        },
        { 
          args = { "build" }, 
          name = "nix build", 
          tags = { TAG.BUILD },
          desc = "Build default package"
        },
        { 
          args = { "run" }, 
          name = "nix run", 
          tags = { TAG.RUN },
          desc = "Run default application"
        },
        { 
          args = { "flake", "check" }, 
          name = "nix flake check", 
          tags = { TAG.TEST },
          desc = "Run flake checks"
        },
        { 
          args = { "flake", "update" }, 
          name = "nix flake update",
          desc = "Update flake inputs"
        },
      }
    else
      -- Legacy Nix commands
      commands = {
        { 
          args = { "build" }, 
          name = "nix build", 
          tags = { TAG.BUILD },
          desc = "Build with default.nix"
        },
        { 
          args = { "shell" }, 
          name = "nix shell", 
          tags = { TAG.BUILD },
          desc = "Enter Nix shell"
        },
      }
    end
    
    for _, command in ipairs(commands) do
      table.insert(
        ret,
        overseer.wrap_template(
          tmpl,
          {
            name = command.name,
            tags = command.tags,
            desc = command.desc,
          },
          { args = command.args, cwd = cwd }
        )
      )
    end
    
    -- Phase 2: Dynamic discovery for flakes
    if flake_file and nix_config.dynamic_discovery then
      local flake_data = discover_flake_targets(flake_file)
      if flake_data then
        local system = get_current_system()
        local dynamic_templates = generate_dynamic_templates(flake_data, cwd, system)
        
        for _, template_data in ipairs(dynamic_templates) do
          table.insert(
            ret,
            overseer.wrap_template(
              tmpl,
              {
                name = template_data.name,
                tags = template_data.tags,
                desc = template_data.desc,
              },
              { args = template_data.args, cwd = cwd }
            )
          )
        end
      end
    end
    
    -- Add a generic "nix" template for custom commands
    table.insert(
      ret,
      overseer.wrap_template(
        tmpl,
        { name = "nix" },
        { cwd = cwd }
      )
    )
    
    cb(ret)
  end,
}

return provider