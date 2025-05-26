local template = require("overseer.template")

describe("just submodules", function()
  local original_fn_executable
  local original_fs_find
  
  before_each(function()
    original_fn_executable = vim.fn.executable
    original_fs_find = vim.fs.find
    
    -- Mock vim.fn.executable to return 1 for 'just'
    vim.fn.executable = function(cmd)
      if cmd == "just" then
        return 1
      end
      return original_fn_executable(cmd)
    end
    
    -- Mock vim.fs.find to return a justfile
    vim.fs.find = function(predicate, opts)
      if type(predicate) == "function" then
        -- Check if this is looking for justfile
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
  
  it("should handle just projects with submodules", function()
    local just_template = require("overseer.template.just")
    
    -- Mock jobstart to simulate just JSON output with submodules
    local original_jobstart = vim.fn.jobstart
    vim.fn.jobstart = function(cmd, opts)
      -- Simulate just --dump --dump-format json output with submodules
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
          modules = {
            frontend = {
              recipes = {
                dev = {
                  name = "dev",
                  doc = "Start dev server",
                  private = false,
                  parameters = {}
                },
                build = {
                  name = "build",
                  doc = "Build frontend",
                  private = false, 
                  parameters = {}
                }
              }
            },
            backend = {
              recipes = {
                serve = {
                  name = "serve",
                  doc = "Start backend server",
                  private = false,
                  parameters = {}
                }
              },
              modules = {
                api = {
                  recipes = {
                    deploy = {
                      name = "deploy",
                      doc = "Deploy API",
                      private = false,
                      parameters = {}
                    }
                  }
                }
              }
            }
          },
          first = "test"
        }
        
        -- Call the on_stdout callback with the mock data
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
    
    -- Wait for async callback
    vim.wait(100)
    
    -- Restore jobstart
    vim.fn.jobstart = original_jobstart
    
    -- Verify we get templates for root recipes and submodule recipes
    assert.truthy(templates)
    assert.is_true(#templates > 0)
    
    local template_names = {}
    for _, tmpl in ipairs(templates) do
      table.insert(template_names, tmpl.name)
    end
    
    -- Check for root level recipes
    assert.truthy(vim.tbl_contains(template_names, "just test"))
    assert.truthy(vim.tbl_contains(template_names, "just build"))
    
    -- Check for submodule recipes
    assert.truthy(vim.tbl_contains(template_names, "just frontend::dev"))
    assert.truthy(vim.tbl_contains(template_names, "just frontend::build"))
    assert.truthy(vim.tbl_contains(template_names, "just backend::serve"))
    
    -- Check for nested submodule recipes
    assert.truthy(vim.tbl_contains(template_names, "just backend::api::deploy"))
    
    -- Verify the first recipe has higher priority
    local test_template = nil
    for _, tmpl in ipairs(templates) do
      if tmpl.name == "just test" then
        test_template = tmpl
        break
      end
    end
    assert.truthy(test_template)
    assert.equals(55, test_template.priority)
  end)
end)