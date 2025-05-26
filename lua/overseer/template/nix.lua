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
    
    -- Build components list with Nix-specific components
    local components = { "default" }
    
    -- Add Nix environment component
    table.insert(components, { "nix_env", 
      experimental_features = { "nix-command", "flakes" },
      check_flake_inputs = false,  -- Only check on explicit flake operations
    })
    
    -- Add flake context for flake operations
    if vim.tbl_contains(args, "flake") or vim.tbl_contains(args, "develop") or vim.tbl_contains(args, "build") or vim.tbl_contains(args, "run") then
      table.insert(components, { "nix_flake_context",
        check_flake_lock = true,
        show_flake_info = true,
      })
    end
    
    -- Add build results component for build/run operations
    if vim.tbl_contains(args, "build") or vim.tbl_contains(args, "run") then
      table.insert(components, { "nix_build_results",
        show_build_paths = true,
        result_notification = true,
      })
    end
    
    -- Add timeout component
    table.insert(components, { "timeout", timeout = nix_config.timeout })
    
    return {
      cmd = { "nix" },
      args = args,
      cwd = params.cwd,
      components = components,
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

-- Cache for system detection
local _system_cache = nil

---Get the current system for Nix operations
---@return string|nil
local function get_current_system()
  if nix_config.system then
    return nix_config.system
  end
  
  -- Use cached result if available
  if _system_cache then
    return _system_cache
  end
  
  -- Try to get current system from Nix
  local result = vim.system({ "nix", "eval", "--impure", "--expr", "builtins.currentSystem" }, {
    timeout = 5000,  -- 5 second timeout for system detection
  }):wait()
  
  if result.code == 0 and result.stdout then
    local system = result.stdout:gsub('"', ""):gsub("\n", ""):gsub("\r", "")
    if system and system ~= "" then
      _system_cache = system  -- Cache the result
      log:debug("Detected Nix system: %s", system)
      return system
    end
  else
    log:warn("Failed to detect current Nix system: %s", result.stderr or "unknown error")
  end
  
  return nil
end


-- Cache for flake discovery results
local _flake_cache = {}

---Parse `nix flake show --json` output to discover targets with comprehensive error handling
---@param flake_path string
---@return table|nil, string|nil error_message
local function discover_flake_targets(flake_path)
  if not nix_config.dynamic_discovery then
    return nil, "Dynamic discovery disabled"
  end
  
  -- Check if Nix is available
  if vim.fn.executable("nix") == 0 then
    return nil, "Nix command not found"
  end
  
  -- Check cache first
  local cache_key = flake_path
  if nix_config.cache_discovery and _flake_cache[cache_key] then
    local cached = _flake_cache[cache_key]
    -- Check if cache is still valid (flake.nix hasn't changed)
    local flake_stat = vim.loop.fs_stat(flake_path)
    if flake_stat and cached.mtime == flake_stat.mtime.sec then
      log:debug("Using cached flake data for %s", flake_path)
      return cached.data, nil
    end
  end
  
  local cwd = vim.fs.dirname(flake_path)
  
  -- Check if flake.nix is readable
  local flake_content = vim.fn.readfile(flake_path, '', 1)
  if vim.tbl_isempty(flake_content) then
    return nil, "flake.nix is empty or unreadable"
  end
  
  -- Build the command (try --all-systems first for better discovery)
  local cmd = { "nix", "flake", "show", "--json", "--all-systems" }
  local fallback_attempts = {
    { "nix", "flake", "show", "--json" },  -- Without --all-systems
    { "nix", "flake", "show", "--json", "--no-eval-cache" },  -- Without eval cache
  }
  
  log:debug("Running nix flake show for %s", flake_path)
  
  -- Try main command first
  local result = vim.system(cmd, {
    cwd = cwd,
    timeout = nix_config.timeout,
  }):wait()
  
  -- Try fallback commands if main command fails
  if result.code ~= 0 then
    local last_error = result.stderr or "unknown error"
    
    for i, fallback_cmd in ipairs(fallback_attempts) do
      log:debug("Attempt %d: trying fallback command: %s", i, table.concat(fallback_cmd, " "))
      result = vim.system(fallback_cmd, {
        cwd = cwd,
        timeout = math.min(nix_config.timeout, 15000),  -- Shorter timeout for fallbacks
      }):wait()
      
      if result.code == 0 then
        log:debug("Fallback attempt %d succeeded", i)
        break
      else
        last_error = result.stderr or last_error
      end
    end
    
    if result.code ~= 0 then
      -- Categorize the error for better user feedback
      local error_msg = "nix flake show failed"
      if last_error then
        if last_error:match("experimental%-features") then
          error_msg = "Nix experimental features not enabled. Add 'experimental-features = nix-command flakes' to nix.conf"
        elseif last_error:match("not a flake") then
          error_msg = "Directory does not contain a valid flake"
        elseif last_error:match("network") or last_error:match("fetch") then
          error_msg = "Network error while fetching flake inputs"
        elseif last_error:match("evaluation") or last_error:match("infinite recursion") then
          error_msg = "Flake evaluation error (syntax or logic issue)"
        elseif last_error:match("timeout") then
          error_msg = "Flake discovery timed out (flake may be too complex)"
        else
          error_msg = string.format("nix flake show failed: %s", last_error:sub(1, 100))
        end
      end
      
      log:warn("%s (exit code %d)", error_msg, result.code)
      return nil, error_msg
    end
  end
  
  local output = result.stdout
  if not output or output == "" then
    log:debug("nix flake show returned empty output")
    return nil, "nix flake show returned empty output"
  end
  
  -- Parse JSON output with error handling
  local ok, parsed = pcall(json.decode, output)
  if not ok then
    log:warn("Failed to parse nix flake show JSON output: %s", parsed)
    return nil, "Failed to parse JSON output from nix flake show"
  end
  
  -- Validate parsed data structure
  if type(parsed) ~= "table" then
    return nil, "Invalid flake show output format"
  end
  
  -- Cache the result
  if nix_config.cache_discovery then
    local flake_stat = vim.loop.fs_stat(flake_path)
    if flake_stat then
      _flake_cache[cache_key] = {
        data = parsed,
        mtime = flake_stat.mtime.sec
      }
      log:debug("Cached flake discovery result for %s", flake_path)
    end
  end
  
  return parsed, nil
end

---Get all available systems from flake
---@param flake_path string
---@return string[]
local function get_available_systems(flake_path)
  local flake_data, error_msg = discover_flake_targets(flake_path)
  local systems = {}
  
  if not flake_data then
    if error_msg then
      log:debug("Failed to get available systems: %s", error_msg)
    end
    return systems
  end
  
  -- Collect systems from packages, apps, devShells, and checks
  for _, section in ipairs({"packages", "apps", "devShells", "checks"}) do
    if flake_data[section] then
      for system, _ in pairs(flake_data[section]) do
        if not vim.tbl_contains(systems, system) then
          table.insert(systems, system)
        end
      end
    end
  end
  
  log:debug("Available systems: %s", vim.inspect(systems))
  return systems
end

---Generate templates for specific flake targets
---@param flake_data table
---@param cwd string
---@param target_system string|nil
---@return table[]
local function generate_dynamic_templates(flake_data, cwd, target_system)
  local templates = {}
  local current_system = target_system or get_current_system()
  
  if not flake_data then
    return templates
  end
  
  -- Get all available systems if no specific system is targeted
  local systems_to_process = {}
  if current_system then
    table.insert(systems_to_process, current_system)
  else
    -- If we can't detect current system, try to find available systems
    for _, section in ipairs({"packages", "apps", "devShells", "checks"}) do
      if flake_data[section] then
        for system, _ in pairs(flake_data[section]) do
          if not vim.tbl_contains(systems_to_process, system) then
            table.insert(systems_to_process, system)
          end
        end
      end
    end
  end
  
  for _, system in ipairs(systems_to_process) do
    local system_suffix = (#systems_to_process > 1) and string.format(" (%s)", system) or ""
    
    -- Generate templates for packages
    if flake_data.packages and flake_data.packages[system] then
      for package_name, package_info in pairs(flake_data.packages[system]) do
        if package_name ~= "default" then  -- Skip default, it's already covered
          local template_name = string.format("nix build .#%s", package_name)
          if #systems_to_process > 1 then
            template_name = template_name .. system_suffix
          end
          table.insert(templates, {
            name = template_name,
            tags = { TAG.BUILD },
            desc = string.format("Build package '%s'%s", package_name, system_suffix),
            args = { "build", string.format(".#%s", package_name) },
            system = system,
          })
        end
      end
    end
    
    -- Generate templates for apps
    if flake_data.apps and flake_data.apps[system] then
      for app_name, app_info in pairs(flake_data.apps[system]) do
        if app_name ~= "default" then  -- Skip default, it's already covered
          local template_name = string.format("nix run .#%s", app_name)
          if #systems_to_process > 1 then
            template_name = template_name .. system_suffix
          end
          table.insert(templates, {
            name = template_name,
            tags = { TAG.RUN },
            desc = string.format("Run application '%s'%s", app_name, system_suffix),
            args = { "run", string.format(".#%s", app_name) },
            system = system,
          })
        end
      end
    end
    
    -- Generate templates for devShells
    if flake_data.devShells and flake_data.devShells[system] then
      for shell_name, shell_info in pairs(flake_data.devShells[system]) do
        if shell_name ~= "default" then  -- Skip default, it's already covered
          local template_name = string.format("nix develop .#%s", shell_name)
          if #systems_to_process > 1 then
            template_name = template_name .. system_suffix
          end
          table.insert(templates, {
            name = template_name,
            tags = { TAG.BUILD },
            desc = string.format("Enter development shell '%s'%s", shell_name, system_suffix),
            args = { "develop", string.format(".#%s", shell_name) },
            system = system,
          })
        end
      end
    end
    
    -- Generate templates for checks
    if flake_data.checks and flake_data.checks[system] then
      for check_name, check_info in pairs(flake_data.checks[system]) do
        local template_name = string.format("nix build .#checks.%s.%s", system, check_name)
        if #systems_to_process > 1 then
          template_name = template_name .. system_suffix
        end
        table.insert(templates, {
          name = template_name,
          tags = { TAG.TEST },
          desc = string.format("Run check '%s'%s", check_name, system_suffix),
          args = { "build", string.format(".#checks.%s.%s", system, check_name) },
          system = system,
        })
      end
    end
  end
  
  return templates
end

---Check for legacy shell.nix files
---@param opts overseer.SearchParams
---@return string|nil
local function get_shell_nix_file(opts)
  if not nix_config.legacy_support then
    return nil
  end
  return vim.fs.find("shell.nix", { upward = true, type = "file", path = opts.dir })[1]
end

---Generate templates for legacy Nix files
---@param nix_file string
---@param cwd string
---@return table[]
local function generate_legacy_templates(nix_file, cwd)
  local templates = {}
  local filename = vim.fs.basename(nix_file)
  
  if filename == "shell.nix" then
    -- shell.nix specific commands
    table.insert(templates, {
      name = "nix-shell",
      tags = { TAG.BUILD },
      desc = "Enter Nix shell from shell.nix",
      args = { "nix-shell" },
    })
    table.insert(templates, {
      name = "nix develop -f shell.nix",
      tags = { TAG.BUILD },
      desc = "Enter development shell from shell.nix",
      args = { "develop", "-f", "shell.nix" },
    })
  elseif filename == "default.nix" then
    -- default.nix specific commands
    table.insert(templates, {
      name = "nix-build",
      tags = { TAG.BUILD },
      desc = "Build with nix-build",
      args = { "nix-build" },
    })
    table.insert(templates, {
      name = "nix build -f default.nix",
      tags = { TAG.BUILD },
      desc = "Build with default.nix",
      args = { "build", "-f", "default.nix" },
    })
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
      local shell_file = get_shell_nix_file(opts)
      if not flake_file and not legacy_file and not shell_file then
        return false, "No flake.nix, default.nix, or shell.nix file found"
      end
      return true
    end,
  },
  generator = function(opts, cb)
    local flake_file = get_flake_file(opts)
    local legacy_file = get_legacy_nix_file(opts)
    local shell_file = get_shell_nix_file(opts)
    local nix_file = flake_file or legacy_file or shell_file
    
    if not nix_file then
      cb({})
      return
    end
    
    local cwd = vim.fs.dirname(nix_file)
    local ret = {}
    
    -- Phase 1: Static common commands
    local commands = {}
    
    if flake_file then
      -- Get available systems for this flake
      local available_systems = get_available_systems(flake_file)
      local current_system = get_current_system()
      
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
      
      -- Add system-specific variants if multiple systems are available
      if #available_systems > 1 then
        for _, system in ipairs(available_systems) do
          if system ~= current_system then
            table.insert(commands, {
              args = { "build", "--system", system },
              name = string.format("nix build (%s)", system),
              tags = { TAG.BUILD },
              desc = string.format("Build default package for %s", system)
            })
          end
        end
      end
    else
      -- Legacy Nix commands
      local legacy_templates = generate_legacy_templates(nix_file, cwd)
      for _, template_data in ipairs(legacy_templates) do
        table.insert(commands, template_data)
      end
      
      -- Add generic legacy commands if none were generated
      if #commands == 0 then
        commands = {
          { 
            args = { "build" }, 
            name = "nix build", 
            tags = { TAG.BUILD },
            desc = "Build with legacy Nix file"
          },
          { 
            args = { "shell" }, 
            name = "nix shell", 
            tags = { TAG.BUILD },
            desc = "Enter Nix shell"
          },
        }
      end
    end
    
    for _, command in ipairs(commands) do
      local default_params = { args = command.args, cwd = cwd }
      if command.system then
        default_params.system = command.system
      end
      
      table.insert(
        ret,
        overseer.wrap_template(
          tmpl,
          {
            name = command.name,
            tags = command.tags,
            desc = command.desc,
          },
          default_params
        )
      )
    end
    
    -- Phase 2: Dynamic discovery for flakes
    if flake_file and nix_config.dynamic_discovery then
      local flake_data, error_msg = discover_flake_targets(flake_file)
      if flake_data then
        local system = get_current_system()
        local dynamic_templates = generate_dynamic_templates(flake_data, cwd, system)
        
        for _, template_data in ipairs(dynamic_templates) do
          local default_params = { args = template_data.args, cwd = cwd }
          if template_data.system then
            default_params.system = template_data.system
          end
          
          table.insert(
            ret,
            overseer.wrap_template(
              tmpl,
              {
                name = template_data.name,
                tags = template_data.tags,
                desc = template_data.desc,
              },
              default_params
            )
          )
        end
      elseif error_msg then
        -- Add a diagnostic template when discovery fails
        table.insert(
          ret,
          overseer.wrap_template(
            tmpl,
            {
              name = "nix flake show (failed)",
              desc = string.format("Flake discovery failed: %s", error_msg),
              tags = { "diagnostic" },
            },
            { 
              args = { "flake", "show" }, 
              cwd = cwd,
              -- Add extra diagnostic info
              extra_args = { "--show-trace" },
            }
          )
        )
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