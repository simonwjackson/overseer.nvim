local log = require("overseer.log")
local util = require("overseer.util")

---@type overseer.ComponentFileDefinition
local comp = {
  desc = "Handle Nix flake context and metadata",
  params = {
    auto_update_inputs = {
      desc = "Automatically update flake inputs if they're outdated",
      type = "boolean",
      default = false,
      optional = true,
    },
    check_flake_lock = {
      desc = "Verify flake.lock is up to date before building",
      type = "boolean",
      default = true,
      optional = true,
    },
    show_flake_info = {
      desc = "Display flake metadata in task output",
      type = "boolean",
      default = true,
      optional = true,
    },
    max_input_age_days = {
      desc = "Maximum age of flake inputs in days before warning",
      type = "number",
      default = 30,
      optional = true,
    },
  },
  editable = true,
  serializable = true,
  constructor = function(params)
    return {
      flake_metadata = {},
      flake_inputs = {},
      
      on_init = function(self, task)
        -- Find flake.nix in task directory or parent directories
        if task.cwd then
          local flake_file = vim.fs.find("flake.nix", { path = task.cwd, upward = true, type = "file" })[1]
          if flake_file then
            self.flake_dir = vim.fs.dirname(flake_file)
            self.flake_file = flake_file
            log:debug("Found flake.nix at: %s", flake_file)
            
            -- Load flake metadata
            self:load_flake_metadata()
          end
        end
      end,
      
      load_flake_metadata = function(self)
        if not self.flake_dir then
          return
        end
        
        -- Get flake metadata
        local metadata_result = vim.system(
          { "nix", "flake", "metadata", "--json" },
          { cwd = self.flake_dir, timeout = 10000 }
        ):wait()
        
        if metadata_result.code == 0 and metadata_result.stdout then
          local ok, metadata = pcall(vim.json.decode, metadata_result.stdout)
          if ok then
            self.flake_metadata = metadata
            log:debug("Loaded flake metadata: %s", metadata.url or "unknown")
            
            -- Extract input information
            if metadata.locks and metadata.locks.nodes then
              for name, node in pairs(metadata.locks.nodes) do
                if node.locked and name ~= "root" then
                  self.flake_inputs[name] = {
                    rev = node.locked.rev,
                    lastModified = node.locked.lastModified,
                    type = node.locked.type,
                    url = node.locked.url or node.original.url,
                  }
                end
              end
            end
          end
        else
          log:warn("Failed to load flake metadata: %s", metadata_result.stderr or "unknown error")
        end
      end,
      
      check_input_freshness = function(self)
        local warnings = {}
        local current_time = os.time()
        local max_age_seconds = params.max_input_age_days * 24 * 60 * 60
        
        for name, input in pairs(self.flake_inputs) do
          if input.lastModified then
            local age_seconds = current_time - input.lastModified
            if age_seconds > max_age_seconds then
              local age_days = math.floor(age_seconds / (24 * 60 * 60))
              table.insert(warnings, string.format("Input '%s' is %d days old", name, age_days))
            end
          end
        end
        
        return warnings
      end,
      
      on_pre_start = function(self, task)
        if not self.flake_dir then
          return true  -- Not a flake project, continue normally
        end
        
        -- Check flake.lock consistency
        if params.check_flake_lock then
          local lock_file = self.flake_dir .. "/flake.lock"
          local lock_stat = vim.loop.fs_stat(lock_file)
          local flake_stat = vim.loop.fs_stat(self.flake_file)
          
          if lock_stat and flake_stat then
            if flake_stat.mtime.sec > lock_stat.mtime.sec then
              log:warn("flake.nix is newer than flake.lock. Consider running 'nix flake update'")
            end
          elseif not lock_stat then
            log:warn("flake.lock not found. Running 'nix flake update' first...")
            if params.auto_update_inputs then
              local update_result = vim.system(
                { "nix", "flake", "update" },
                { cwd = self.flake_dir, timeout = 30000 }
              ):wait()
              
              if update_result.code ~= 0 then
                log:error("Failed to update flake inputs: %s", update_result.stderr or "unknown error")
                return false
              end
              
              -- Reload metadata after update
              self:load_flake_metadata()
            end
          end
        end
        
        -- Check input freshness
        local warnings = self:check_input_freshness()
        for _, warning in ipairs(warnings) do
          log:warn(warning)
        end
        
        if #warnings > 0 and params.auto_update_inputs then
          log:info("Auto-updating outdated flake inputs...")
          local update_result = vim.system(
            { "nix", "flake", "update" },
            { cwd = self.flake_dir, timeout = 60000 }
          ):wait()
          
          if update_result.code == 0 then
            log:info("Successfully updated flake inputs")
            self:load_flake_metadata()
          else
            log:warn("Failed to auto-update inputs: %s", update_result.stderr or "unknown error")
          end
        end
        
        return true
      end,
      
      on_result = function(self, task, result)
        if self.flake_metadata and not vim.tbl_isempty(self.flake_metadata) then
          result.nix_flake_metadata = {
            url = self.flake_metadata.url,
            description = self.flake_metadata.description,
            inputs = vim.tbl_keys(self.flake_inputs),
            input_count = vim.tbl_count(self.flake_inputs),
          }
        end
      end,
      
      render = function(self, task, lines, highlights, detail)
        if not params.show_flake_info or not self.flake_metadata then
          return
        end
        
        if detail >= 2 then
          table.insert(lines, "Flake Information:")
          
          if self.flake_metadata.description then
            table.insert(lines, "  Description: " .. self.flake_metadata.description)
          end
          
          if self.flake_metadata.url then
            table.insert(lines, "  URL: " .. self.flake_metadata.url)
          end
          
          local input_count = vim.tbl_count(self.flake_inputs)
          if input_count > 0 then
            table.insert(lines, string.format("  Inputs: %d", input_count))
            
            if detail >= 3 then
              local sorted_inputs = {}
              for name, _ in pairs(self.flake_inputs) do
                table.insert(sorted_inputs, name)
              end
              table.sort(sorted_inputs)
              
              for i, name in ipairs(sorted_inputs) do
                if i <= 5 then  -- Limit to first 5 inputs
                  local input = self.flake_inputs[name]
                  local line = string.format("    %s", name)
                  if input.rev then
                    line = line .. string.format(" (%s)", input.rev:sub(1, 8))
                  end
                  table.insert(lines, line)
                elseif i == 6 then
                  table.insert(lines, string.format("    ... and %d more", #sorted_inputs - 5))
                  break
                end
              end
            end
          end
        elseif detail >= 1 and vim.tbl_count(self.flake_inputs) > 0 then
          table.insert(lines, string.format("Flake inputs: %d", vim.tbl_count(self.flake_inputs)))
        end
      end,
    }
  end,
}

return comp