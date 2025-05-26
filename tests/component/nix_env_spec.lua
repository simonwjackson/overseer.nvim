local nix_env_comp = require("overseer.component.nix_env")

describe("nix_env component", function()
  local test_dir
  local original_executable
  local original_system

  before_each(function()
    original_executable = vim.fn.executable
    original_system = vim.system
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    
    -- Mock nix as available by default
    vim.fn.executable = function(cmd)
      if cmd == "nix" then
        return 1
      end
      return original_executable(cmd)
    end
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
    vim.fn.executable = original_executable
    vim.system = original_system
  end)

  describe("on_pre_start", function()
    it("should fail when nix command is not available", function()
      -- Mock vim.fn.executable to return 0 (not found)
      vim.fn.executable = function(cmd)
        if cmd == "nix" then
          return 0
        end
        return original_executable(cmd)
      end

      local component = nix_env_comp.constructor({})
      local task = { env = {} }
      
      local result = component.on_pre_start(component, task)
      assert.is_false(result)
    end)

    it("should set up Nix environment variables", function()
      -- Mock vim.system for nix --version
      vim.system = function(cmd, opts)
        if cmd[1] == "nix" and cmd[2] == "--version" then
          return {
            wait = function()
              return {
                code = 0,
                stdout = "nix (Nix) 2.19.2",
                stderr = ""
              }
            end
          }
        end
        return original_system(cmd, opts)
      end

      local component = nix_env_comp.constructor({
        experimental_features = { "nix-command", "flakes" },
        nix_path_override = "/custom/nix/path",
        max_jobs = 4
      })
      
      local task = { env = {} }
      
      local result = component.on_pre_start(component, task)
      assert.is_true(result)
      
      -- Check that environment variables were set
      assert.equals("/custom/nix/path", task.env.NIX_PATH)
      assert.equals("4", task.env.NIX_BUILD_CORES)
      assert.equals("experimental-features = nix-command flakes", task.env.NIX_CONFIG)
    end)

    it("should check flake inputs when requested", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local nix_calls = {}
      vim.system = function(cmd, opts)
        table.insert(nix_calls, { cmd = cmd, opts = opts })
        if cmd[1] == "nix" and cmd[2] == "--version" then
          return {
            wait = function()
              return {
                code = 0,
                stdout = "nix (Nix) 2.19.2",
                stderr = ""
              }
            end
          }
        elseif cmd[1] == "nix" and cmd[2] == "flake" and cmd[3] == "check" then
          return {
            wait = function()
              return {
                code = 0,
                stdout = "",
                stderr = ""
              }
            end
          }
        end
        return original_system(cmd, opts)
      end

      local component = nix_env_comp.constructor({
        check_flake_inputs = true
      })
      
      local task = { env = {}, cwd = test_dir }
      
      local result = component.on_pre_start(component, task)
      assert.is_true(result)
      
      -- Should have called nix flake check
      local flake_check_called = false
      for _, call in ipairs(nix_calls) do
        if call.cmd[2] == "flake" and call.cmd[3] == "check" then
          flake_check_called = true
          assert.equals(test_dir, call.opts.cwd)
          break
        end
      end
      assert.is_true(flake_check_called)
    end)
  end)

  describe("on_exit", function()
    it("should provide helpful error messages for common failures", function()
      local component = nix_env_comp.constructor({})
      
      -- Create mock task with buffer containing error output
      local mock_bufnr = 1
      local task = {
        get_bufnr = function() return mock_bufnr end
      }
      
      -- Mock vim.api.nvim_buf_get_lines to return specific error content
      local original_buf_get_lines = vim.api.nvim_buf_get_lines
      vim.api.nvim_buf_get_lines = function(bufnr, start, end_, strict)
        if bufnr == mock_bufnr then
          return {
            "error: experimental-features 'nix-command flakes' are required",
            "but not enabled in nix.conf"
          }
        end
        return original_buf_get_lines(bufnr, start, end_, strict)
      end
      
      -- Call on_exit with failure code
      component.on_exit(component, task, 1)
      
      -- Restore original function
      vim.api.nvim_buf_get_lines = original_buf_get_lines
      
      -- Note: We can't easily test the log output without mocking the log module
      -- But the function should complete without error
    end)
  end)

  describe("render", function()
    it("should display environment information in detailed view", function()
      local component = nix_env_comp.constructor({})
      local task = {
        env = {
          NIX_PATH = "/custom/path",
          NIX_BUILD_CORES = "8",
          NIX_CONFIG = "experimental-features = nix-command flakes"
        }
      }
      
      local lines = {}
      local highlights = {}
      
      component.render(component, task, lines, highlights, 2)
      
      -- Should include environment information
      assert.is_true(#lines > 0)
      assert.has.truthy(vim.tbl_contains(lines, "Nix Environment:"))
      
      -- Check for specific environment variables
      local found_nix_path = false
      local found_build_cores = false
      for _, line in ipairs(lines) do
        if line:match("NIX_PATH: /custom/path") then
          found_nix_path = true
        elseif line:match("Build cores: 8") then
          found_build_cores = true
        end
      end
      assert.is_true(found_nix_path)
      assert.is_true(found_build_cores)
    end)

    it("should not display environment info in minimal detail view", function()
      local component = nix_env_comp.constructor({})
      local task = {
        env = {
          NIX_PATH = "/custom/path"
        }
      }
      
      local lines = {}
      local highlights = {}
      
      component.render(component, task, lines, highlights, 1)
      
      -- Should not include environment information at detail level 1
      assert.is_false(vim.tbl_contains(lines, "Nix Environment:"))
    end)
  end)
end)