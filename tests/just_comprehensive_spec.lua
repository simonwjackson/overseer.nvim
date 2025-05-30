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
  
  it("should expand variable references in parameter defaults", function()
    local just_template = require("overseer.template.just")
    
    local original_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      if cmd[1] == "just" and vim.tbl_contains(cmd, "--dump") then
        local mock_data = {
          assignments = {
            x = { value = "1", name = "x", export = false, private = false },
            y = { value = "hello world", name = "y", export = false, private = false }
          },
          recipes = {
            ["test-basic"] = {
              name = "test-basic",
              doc = "Test recipe with variable default",
              private = false,
              parameters = {
                {
                  name = "arg",
                  kind = "singular",
                  default = { "variable", "x" }
                }
              }
            },
            ["test-string"] = {
              name = "test-string",
              doc = "Test recipe with string variable default",
              private = false,
              parameters = {
                {
                  name = "name",
                  kind = "singular",
                  default = { "variable", "y" }
                }
              }
            },
            ["test-undefined"] = {
              name = "test-undefined",
              doc = "Test recipe with undefined variable",
              private = false,
              parameters = {
                {
                  name = "missing",
                  kind = "singular",
                  default = { "variable", "undefined_var" }
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
    
    assert.equals(3, #templates)
    
    -- Find each template and check variable expansion
    local test_basic, test_string, test_undefined
    for _, tmpl in ipairs(templates) do
      if tmpl.name == "just test-basic" then
        test_basic = tmpl
      elseif tmpl.name == "just test-string" then
        test_string = tmpl
      elseif tmpl.name == "just test-undefined" then
        test_undefined = tmpl
      end
    end
    
    -- Test variable x expansion
    assert.truthy(test_basic)
    assert.truthy(test_basic.params.arg)
    assert.equals("1", test_basic.params.arg.default)
    
    -- Test variable y expansion  
    assert.truthy(test_string)
    assert.truthy(test_string.params.name)
    assert.equals("hello world", test_string.params.name.default)
    
    -- Test undefined variable fallback
    assert.truthy(test_undefined)
    assert.truthy(test_undefined.params.missing)
    assert.equals("undefined_var", test_undefined.params.missing.default)
  end)
end)