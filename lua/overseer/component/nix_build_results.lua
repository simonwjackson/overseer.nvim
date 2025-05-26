local log = require("overseer.log")
local util = require("overseer.util")

---@type overseer.ComponentFileDefinition
local comp = {
  desc = "Parse and track Nix build results",
  params = {
    show_build_paths = {
      desc = "Display paths of built derivations",
      type = "boolean",
      default = true,
      optional = true,
    },
    show_runtime_deps = {
      desc = "Show runtime dependencies of built packages",
      type = "boolean",
      default = false,
      optional = true,
    },
    copy_result_to_clipboard = {
      desc = "Copy build result path to clipboard",
      type = "boolean",
      default = false,
      optional = true,
    },
    result_notification = {
      desc = "Show notification with build result",
      type = "boolean",
      default = true,
      optional = true,
    },
  },
  editable = true,
  serializable = true,
  constructor = function(params)
    return {
      build_results = {},
      store_paths = {},
      
      on_output_lines = function(self, task, lines)
        for _, line in ipairs(lines) do
          -- Parse store paths from Nix output
          local store_path = line:match("(/nix/store/[%w%-%.%+_]+[%w%-%.%+_/]*)")
          if store_path then
            if not vim.tbl_contains(self.store_paths, store_path) then
              table.insert(self.store_paths, store_path)
              log:debug("Found Nix store path: %s", store_path)
            end
          end
          
          -- Parse build results
          local result_path = line:match("^(/nix/store/[%w%-%.%+_]+)$")
          if result_path and not vim.tbl_contains(self.build_results, result_path) then
            table.insert(self.build_results, result_path)
            log:debug("Found build result: %s", result_path)
          end
          
          -- Parse substitution information
          if line:match("copying path") or line:match("downloading") then
            log:debug("Nix substitution: %s", line)
          end
          
          -- Parse build progress
          if line:match("building") or line:match("built") then
            log:debug("Build progress: %s", line)
          end
        end
      end,
      
      on_result = function(self, task, result)
        if #self.build_results > 0 then
          result.nix_build_results = vim.deepcopy(self.build_results)
          result.nix_store_paths = vim.deepcopy(self.store_paths)
          
          -- Get information about built packages
          for _, path in ipairs(self.build_results) do
            -- Try to get package metadata
            local info_result = vim.system({ "nix", "path-info", "--json", path }, { timeout = 5000 }):wait()
            if info_result.code == 0 and info_result.stdout then
              local ok, path_info = pcall(vim.json.decode, info_result.stdout)
              if ok and path_info and path_info[1] then
                local info = path_info[1]
                if not result.nix_path_info then
                  result.nix_path_info = {}
                end
                result.nix_path_info[path] = {
                  narSize = info.narSize,
                  references = info.references or {},
                  deriver = info.deriver,
                }
              end
            end
          end
          
          -- Copy result to clipboard if requested
          if params.copy_result_to_clipboard and #self.build_results > 0 then
            local result_path = self.build_results[1]  -- Copy the first result
            vim.fn.setreg("+", result_path)
            log:info("Copied build result to clipboard: %s", result_path)
          end
        end
      end,
      
      on_complete = function(self, task, status, result)
        if params.result_notification and status == "SUCCESS" and #self.build_results > 0 then
          local message = string.format("Nix build completed: %d result(s)", #self.build_results)
          if #self.build_results == 1 then
            local path = self.build_results[1]
            local basename = vim.fs.basename(path)
            message = string.format("Built: %s", basename)
          end
          
          vim.notify(message, vim.log.levels.INFO, {
            title = "Nix Build",
            timeout = 3000,
          })
        end
        
        if params.show_runtime_deps and #self.build_results > 0 then
          -- Show runtime dependencies for built packages
          for _, path in ipairs(self.build_results) do
            local deps_result = vim.system({ "nix", "path-info", "-r", path }, { timeout = 10000 }):wait()
            if deps_result.code == 0 and deps_result.stdout then
              local deps = vim.split(deps_result.stdout, "\n", { trimempty = true })
              log:info("Runtime dependencies for %s: %d packages", vim.fs.basename(path), #deps)
              for _, dep in ipairs(deps) do
                if dep ~= path then  -- Don't include the package itself
                  log:debug("  %s", vim.fs.basename(dep))
                end
              end
            end
          end
        end
      end,
      
      render = function(self, task, lines, highlights, detail)
        if params.show_build_paths and #self.build_results > 0 then
          table.insert(lines, string.format("Build Results (%d):", #self.build_results))
          
          if detail >= 2 then
            for i, path in ipairs(self.build_results) do
              if i <= 5 then  -- Limit display to first 5 results
                table.insert(lines, "  " .. vim.fs.basename(path))
                if detail >= 3 then
                  table.insert(lines, "    " .. path)
                end
              elseif i == 6 then
                table.insert(lines, string.format("  ... and %d more", #self.build_results - 5))
                break
              end
            end
          else
            -- Just show count and first result
            local first = vim.fs.basename(self.build_results[1])
            if #self.build_results == 1 then
              table.insert(lines, "  " .. first)
            else
              table.insert(lines, string.format("  %s (+%d more)", first, #self.build_results - 1))
            end
          end
        end
        
        if detail >= 3 and #self.store_paths > #self.build_results then
          local other_paths = #self.store_paths - #self.build_results
          table.insert(lines, string.format("Other store paths: %d", other_paths))
        end
      end,
    }
  end,
}

return comp