local log = require("overseer.log")

---@type overseer.ComponentFileDefinition
local comp = {
  desc = "Ensure Nix environment is properly configured",
  params = {
    check_flake_inputs = {
      desc = "Check if flake inputs are up to date",
      type = "boolean",
      default = false,
      optional = true,
    },
    experimental_features = {
      desc = "Required Nix experimental features",
      type = "list",
      delimiter = " ",
      default = { "nix-command", "flakes" },
      optional = true,
    },
    nix_path_override = {
      desc = "Override NIX_PATH environment variable",
      type = "string",
      optional = true,
    },
    max_jobs = {
      desc = "Maximum number of build jobs",
      type = "number",
      optional = true,
    },
  },
  editable = true,
  serializable = true,
  constructor = function(params)
    return {
      on_pre_start = function(self, task)
        -- Check if Nix is available
        if vim.fn.executable("nix") == 0 then
          log:error("Nix command not found. Please install Nix.")
          return false
        end
        
        -- Check Nix version and experimental features
        local result = vim.system({ "nix", "--version" }):wait()
        if result.code ~= 0 then
          log:error("Failed to get Nix version: %s", result.stderr or "unknown error")
          return false
        end
        
        log:debug("Nix version: %s", result.stdout:gsub("\n", ""))
        
        -- Set up environment variables
        local env = task.env or {}
        
        -- Override NIX_PATH if specified
        if params.nix_path_override then
          env.NIX_PATH = params.nix_path_override
          log:debug("Set NIX_PATH to: %s", params.nix_path_override)
        end
        
        -- Set max jobs if specified
        if params.max_jobs then
          env.NIX_BUILD_CORES = tostring(params.max_jobs)
          log:debug("Set NIX_BUILD_CORES to: %s", params.max_jobs)
        end
        
        -- Ensure experimental features are enabled
        if params.experimental_features and #params.experimental_features > 0 then
          local features = table.concat(params.experimental_features, " ")
          env.NIX_CONFIG = string.format("experimental-features = %s", features)
          log:debug("Set experimental features: %s", features)
        end
        
        task.env = env
        
        -- Check flake inputs if requested
        if params.check_flake_inputs and task.cwd then
          local flake_file = vim.fs.find("flake.nix", { path = task.cwd, type = "file" })[1]
          if flake_file then
            log:debug("Checking flake inputs for staleness...")
            local check_result = vim.system(
              { "nix", "flake", "check", "--no-build" },
              { cwd = task.cwd, timeout = 10000 }
            ):wait()
            
            if check_result.code ~= 0 then
              log:warn("Flake check failed, inputs may be stale: %s", check_result.stderr or "")
            else
              log:debug("Flake inputs appear to be up to date")
            end
          end
        end
        
        return true
      end,
      
      on_start = function(self, task)
        log:debug("Nix environment setup completed for task: %s", task.name)
      end,
      
      on_exit = function(self, task, code)
        if code ~= 0 then
          -- Check for common Nix errors and provide helpful messages
          local bufnr = task:get_bufnr()
          if bufnr then
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local output = table.concat(lines, "\n")
            
            if output:match("experimental%-features") then
              log:warn("Task failed due to missing experimental features. Consider enabling 'nix-command' and 'flakes'.")
            elseif output:match("flake%.lock") then
              log:warn("Task failed due to flake.lock issues. Try running 'nix flake update'.")
            elseif output:match("substitutor") or output:match("binary cache") then
              log:warn("Task failed due to binary cache issues. Check your network connection and cache configuration.")
            elseif output:match("out of disk space") then
              log:error("Task failed due to insufficient disk space. Consider running 'nix-collect-garbage'.")
            end
          end
        end
      end,
      
      render = function(self, task, lines, highlights, detail)
        if detail >= 2 then
          local env_info = {}
          
          if task.env then
            if task.env.NIX_PATH then
              table.insert(env_info, "NIX_PATH: " .. task.env.NIX_PATH)
            end
            if task.env.NIX_BUILD_CORES then
              table.insert(env_info, "Build cores: " .. task.env.NIX_BUILD_CORES)
            end
            if task.env.NIX_CONFIG then
              table.insert(env_info, "Config: " .. task.env.NIX_CONFIG)
            end
          end
          
          if #env_info > 0 then
            table.insert(lines, "Nix Environment:")
            for _, info in ipairs(env_info) do
              table.insert(lines, "  " .. info)
            end
          end
        end
      end,
    }
  end,
}

return comp