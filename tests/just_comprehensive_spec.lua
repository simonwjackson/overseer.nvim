local template = require("overseer.template")

describe("just template comprehensive tests", function()
  local original_fn_executable
  local original_fs_find
  
  before_each(function()
    original_fn_executable = vim.fn.executable
    original_fs_find = vim.fs.find
    
    vim.fn.executable = function(cmd)
      if cmd == "just" then
        return 1
      end
      return original_fn_executable(cmd)
    end
    
    vim.fs.find = function(predicate, opts)
      if type(predicate) == "function" then
        if predicate("justfile") then
          return { "/test/justfile" }
        end
      end
      return original_fs_find(predicate, opts)
    end
  end)
  
  after_each(function()
    vim.fn.executable = original_fn_executable
    vim.fs.find = original_fs_find
  end)
  
  it("should handle just projects without submodules", function()
    local just_template = require("overseer.template.just")
    
    local original_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      if cmd[1] == "just" and vim.tbl_contains(cmd, "--dump") then
        local mock_data = {
          recipes = {
            test = {
              name = "test",
              doc = "Run tests",
              private = false,
              parameters = {}
            },
            build = {
              name = "build", 
              doc = "Build project",
              private = false,
              parameters = {}
            }
          },
          first = "test"
        }
        
        vim.schedule(function()
          opts.on_stdout(nil, { vim.json.encode(mock_data) })
        end)
        return 1
      end
      return original_jobstart(cmd, opts)
    end
    
    local templates = {}
    just_template.generator({ dir = "/test" }, function(results)
      templates = results
    end)
    
    vim.wait(100)
    vim.fn.jobstart = original_jobstart
    
    assert.equals(2, #templates)
    
    local template_names = {}
    for _, tmpl in ipairs(templates) do
      table.insert(template_names, tmpl.name)
    end
    
    assert.truthy(vim.tbl_contains(template_names, "just test"))
    assert.truthy(vim.tbl_contains(template_names, "just build"))
  end)
  
  it("should handle parameters in submodule recipes", function()
    local just_template = require("overseer.template.just")
    
    local original_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      if cmd[1] == "just" and vim.tbl_contains(cmd, "--dump") then
        local mock_data = {
          recipes = {},
          modules = {
            frontend = {
              recipes = {
                serve = {
                  name = "serve",
                  doc = "Start dev server",
                  private = false,
                  parameters = {
                    {
                      name = "port",
                      kind = "singular",
                      default = "3000"
                    },
                    {
                      name = "env",
                      kind = "singular",
                      default = nil
                    }
                  }
                }
              }
            }
          }
        }
        
        vim.schedule(function()
          opts.on_stdout(nil, { vim.json.encode(mock_data) })
        end)
        return 1
      end
      return original_jobstart(cmd, opts)
    end
    
    local templates = {}
    just_template.generator({ dir = "/test" }, function(results)
      templates = results
    end)
    
    vim.wait(100)
    vim.fn.jobstart = original_jobstart
    
    assert.equals(1, #templates)
    
    local serve_template = templates[1]
    assert.equals("just frontend::serve", serve_template.name)
    assert.truthy(serve_template.params)
    assert.truthy(serve_template.params.port)
    assert.equals("3000", serve_template.params.port.default)
    assert.truthy(serve_template.params.env)
    
    -- Test the builder function
    local task_def = serve_template.builder({ port = "8080", env = "dev" })
    assert.same({ "just", "frontend::serve", "8080", "dev" }, task_def.cmd)
  end)
  
  it("should skip private recipes in submodules", function()
    local just_template = require("overseer.template.just")
    
    local original_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      if cmd[1] == "just" and vim.tbl_contains(cmd, "--dump") then
        local mock_data = {
          recipes = {},
          modules = {
            utils = {
              recipes = {
                public_task = {
                  name = "public_task",
                  doc = "Public task",
                  private = false,
                  parameters = {}
                },
                _private_task = {
                  name = "_private_task",
                  doc = "Private task",
                  private = true,
                  parameters = {}
                }
              }
            }
          }
        }
        
        vim.schedule(function()
          opts.on_stdout(nil, { vim.json.encode(mock_data) })
        end)
        return 1
      end
      return original_jobstart(cmd, opts)
    end
    
    local templates = {}
    just_template.generator({ dir = "/test" }, function(results)
      templates = results
    end)
    
    vim.wait(100)
    vim.fn.jobstart = original_jobstart
    
    assert.equals(1, #templates)
    assert.equals("just utils::public_task", templates[1].name)
  end)
  
  it("should handle deeply nested submodules", function()
    local just_template = require("overseer.template.just")
    
    local original_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      if cmd[1] == "just" and vim.tbl_contains(cmd, "--dump") then
        local mock_data = {
          recipes = {},
          modules = {
            backend = {
              modules = {
                api = {
                  modules = {
                    v1 = {
                      recipes = {
                        deploy = {
                          name = "deploy",
                          doc = "Deploy v1 API",
                          private = false,
                          parameters = {}
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        
        vim.schedule(function()
          opts.on_stdout(nil, { vim.json.encode(mock_data) })
        end)
        return 1
      end
      return original_jobstart(cmd, opts)
    end
    
    local templates = {}
    just_template.generator({ dir = "/test" }, function(results)
      templates = results
    end)
    
    vim.wait(100)
    vim.fn.jobstart = original_jobstart
    
    assert.equals(1, #templates)
    assert.equals("just backend::api::v1::deploy", templates[1].name)
    assert.equals(65, templates[1].priority) -- Submodule priority
  end)
end)