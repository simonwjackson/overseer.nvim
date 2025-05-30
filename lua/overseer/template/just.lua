local log = require("overseer.log")

---@param opts overseer.SearchParams
---@return nil|string
local function get_justfile(opts)
  local is_justfile = function(name)
    name = name:lower()
    return name == "justfile" or name == ".justfile"
  end
  return vim.fs.find(is_justfile, { upward = true, path = opts.dir })[1]
end

---@type overseer.TemplateFileProvider
local tmpl = {
  cache_key = function(opts)
    return get_justfile(opts)
  end,
  condition = {
    callback = function(opts)
      if vim.fn.executable("just") == 0 then
        return false, 'Command "just" not found'
      end
      if not get_justfile(opts) then
        return false, "No justfile found"
      end
      return true
    end,
  },
  generator = function(opts, cb)
    local ret = {}
    
    -- Helper function to resolve variable references in parameter defaults
    local function resolve_default_value(default_value, assignments)
      -- Validate assignments parameter
      if not assignments then
        log:debug("resolve_default_value called with nil assignments")
        if type(default_value) == "table" and #default_value == 2 and default_value[1] == "variable" then
          return default_value[2] -- Return variable name as fallback
        end
        return default_value
      end
      
      if vim.tbl_isempty(assignments) then
        log:debug("resolve_default_value called with empty assignments table")
      end
      
      if type(default_value) == "table" and #default_value == 2 and default_value[1] == "variable" then
        local var_name = default_value[2]
        log:debug("Looking for variable '%s' in assignments", var_name)
        
        if assignments[var_name] then
          local value = assignments[var_name].value
          log:debug("Found variable '%s' with value: %s", var_name, vim.inspect(value))
          return value
        else
          log:debug("Variable '%s' not found in assignments. Available: %s", 
            var_name, table.concat(vim.tbl_keys(assignments), ", "))
        end
        
        return var_name
      end
      
      return default_value
    end
    
    -- Helper function to process recipes and submodules
    local function process_recipes(recipes, modules, module_path, first_recipe, assignments)
      module_path = module_path or ""
      assignments = assignments or {} -- Ensure assignments is never nil
      
      log:debug("process_recipes called with module_path='%s', assignments=%s", 
        module_path, vim.inspect(vim.tbl_keys(assignments)))
      
      -- Process regular recipes
      for k, recipe in pairs(recipes) do
        if not recipe.private then
          local params_defn = {}
          for _, param in ipairs(recipe.parameters) do
            local param_defn = {
              default = resolve_default_value(param.default, assignments),
              type = param.kind == "singular" and "string" or "list",
              delimiter = " ",
            }
            -- We don't want "star" arguments to be optional = true because then we won't show the
            -- input form. Instead, let's set a default value and filter it out in the builder.
            if param.kind == "star" and param.default == nil then
              if param_defn.type == "string" then
                param_defn.default = ""
              else
                param_defn.default = {}
              end
            end
            params_defn[param.name] = param_defn
          end
          
          local recipe_name = module_path == "" and recipe.name or (module_path .. "::" .. recipe.name)
          local cmd_name = module_path == "" and recipe.name or (module_path .. "::" .. recipe.name)
          
          local is_first = module_path == "" and first_recipe and recipe.name == first_recipe
          table.insert(ret, {
            name = string.format("just %s", recipe_name),
            desc = recipe.doc,
            priority = is_first and 55 or (module_path == "" and 60 or 65),
            params = params_defn,
            builder = function(params)
              local cmd = { "just", cmd_name }
              for _, param in ipairs(recipe.parameters) do
                local v = params[param.name]
                if v then
                  if type(v) == "table" then
                    vim.list_extend(cmd, v)
                  elseif v ~= "" then
                    table.insert(cmd, v)
                  end
                end
              end
              return {
                cmd = cmd,
              }
            end,
          })
        end
      end
      
      -- Process submodules
      if modules then
        for module_name, module_data in pairs(modules) do
          local new_path = module_path == "" and module_name or (module_path .. "::" .. module_name)
          -- Process both recipes and nested modules
          if module_data.recipes or module_data.modules then
            process_recipes(module_data.recipes or {}, module_data.modules, new_path, first_recipe, assignments)
          end
        end
      end
    end
    
    local jid = vim.fn.jobstart({ "just", "--unstable", "--dump", "--dump-format", "json" }, {
      cwd = opts.dir,
      stdout_buffered = true,
      on_stdout = vim.schedule_wrap(function(j, output)
        local ok, data =
          pcall(vim.json.decode, table.concat(output, ""), { luanil = { object = true } })
        if not ok then
          log:error("just produced invalid json: %s\n%s", data, output)
          cb(ret)
          return
        end
        assert(data)
        
        -- Validate and log assignments
        local assignments = data.assignments or {}
        log:debug("Parsed assignments: %s", vim.inspect(assignments))
        log:debug("Assignment count: %d", vim.tbl_count(assignments))
        
        if vim.tbl_isempty(assignments) then
          log:warn("No assignments found in just dump output")
        end
        
        -- Process main recipes and submodules
        process_recipes(data.recipes or {}, data.modules, "", data.first, assignments)
        
        cb(ret)
      end),
    })
    if jid == 0 then
      log:error("Passed invalid arguments to 'just'")
      cb(ret)
    elseif jid == -1 then
      log:error("'just' is not executable")
      cb(ret)
    end
  end,
}

return tmpl
