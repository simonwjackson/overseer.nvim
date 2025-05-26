local constants = require("overseer.constants")
local overseer = require("overseer")
local TAG = constants.TAG

---@type overseer.TemplateFileDefinition
local tmpl = {
  priority = 60,
  params = {
    args = { optional = true, type = "list", delimiter = " " },
    cwd = { optional = true },
  },
  builder = function(params)
    return {
      cmd = { "nix" },
      args = params.args,
      cwd = params.cwd,
    }
  end,
}

---@param opts overseer.SearchParams
---@return string|nil
local function get_flake_file(opts)
  return vim.fs.find("flake.nix", { upward = true, type = "file", path = opts.dir })[1]
end

---@type overseer.TemplateFileProvider
local provider = {
  cache_key = function(opts)
    return get_flake_file(opts)
  end,
  condition = {
    callback = function(opts)
      if vim.fn.executable("nix") == 0 then
        return false, 'Command "nix" not found'
      end
      if not get_flake_file(opts) then
        return false, "No flake.nix file found"
      end
      return true
    end,
  },
  generator = function(opts, cb)
    local flake_file = assert(get_flake_file(opts))
    local cwd = vim.fs.dirname(flake_file)
    
    local ret = {}
    
    -- Phase 1: Static common commands
    local commands = {
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