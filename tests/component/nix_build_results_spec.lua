local nix_build_results_comp = require("overseer.component.nix_build_results")

describe("nix_build_results component", function()
  local original_system
  local original_notify

  before_each(function()
    original_system = vim.system
    original_notify = vim.notify
    
    -- Mock vim.notify to capture notifications
    vim.notify = function(message, level, opts)
      -- Store for testing but don't actually notify
    end
  end)

  after_each(function()
    vim.system = original_system
    vim.notify = original_notify
  end)

  describe("on_output_lines", function()
    it("should parse Nix store paths from output", function()
      local component = nix_build_results_comp.constructor({
        show_build_paths = true
      })
      
      local task = {}
      local output_lines = {
        "copying path '/nix/store/abc123-hello-2.12.1' from 'https://cache.nixos.org'...",
        "building '/nix/store/def456-hello-2.12.1.drv'...",
        "/nix/store/ghi789-hello-2.12.1",
        "some other output",
        "/nix/store/jkl012-dependency-1.0"
      }
      
      component.on_output_lines(component, task, output_lines)
      
      -- Should have found store paths
      assert.equals(4, #component.store_paths)
      assert.has.truthy(vim.tbl_contains(component.store_paths, "/nix/store/abc123-hello-2.12.1"))
      assert.has.truthy(vim.tbl_contains(component.store_paths, "/nix/store/def456-hello-2.12.1.drv"))
      assert.has.truthy(vim.tbl_contains(component.store_paths, "/nix/store/ghi789-hello-2.12.1"))
      assert.has.truthy(vim.tbl_contains(component.store_paths, "/nix/store/jkl012-dependency-1.0"))
      
      -- Should have found build results
      assert.equals(2, #component.build_results)
      assert.has.truthy(vim.tbl_contains(component.build_results, "/nix/store/ghi789-hello-2.12.1"))
      assert.has.truthy(vim.tbl_contains(component.build_results, "/nix/store/jkl012-dependency-1.0"))
    end)

    it("should not duplicate store paths", function()
      local component = nix_build_results_comp.constructor({})
      
      local task = {}
      local output_lines = {
        "/nix/store/abc123-hello-2.12.1",
        "/nix/store/abc123-hello-2.12.1",  -- Duplicate
        "/nix/store/def456-other-1.0"
      }
      
      component.on_output_lines(component, task, output_lines)
      
      -- Should not have duplicates
      assert.equals(2, #component.build_results)
      assert.has.truthy(vim.tbl_contains(component.build_results, "/nix/store/abc123-hello-2.12.1"))
      assert.has.truthy(vim.tbl_contains(component.build_results, "/nix/store/def456-other-1.0"))
    end)
  end)

  describe("on_result", function()
    it("should add build results to task result", function()
      local component = nix_build_results_comp.constructor({})
      
      -- Set up component with some build results
      component.build_results = { "/nix/store/abc123-hello-2.12.1" }
      component.store_paths = { 
        "/nix/store/abc123-hello-2.12.1",
        "/nix/store/def456-dependency-1.0"
      }
      
      -- Mock vim.system for nix path-info
      vim.system = function(cmd, opts)
        if cmd[1] == "nix" and cmd[2] == "path-info" and cmd[3] == "--json" then
          local mock_info = {
            {
              path = "/nix/store/abc123-hello-2.12.1",
              narSize = 12345,
              references = { "/nix/store/def456-dependency-1.0" },
              deriver = "/nix/store/xyz789-hello-2.12.1.drv"
            }
          }
          return {
            wait = function()
              return {
                code = 0,
                stdout = vim.json.encode(mock_info),
                stderr = ""
              }
            end
          }
        end
        return original_system(cmd, opts)
      end
      
      local task = {}
      local result = {}
      
      component.on_result(component, task, result)
      
      -- Should have added build results to result
      assert.is_not_nil(result.nix_build_results)
      assert.equals(1, #result.nix_build_results)
      assert.equals("/nix/store/abc123-hello-2.12.1", result.nix_build_results[1])
      
      assert.is_not_nil(result.nix_store_paths)
      assert.equals(2, #result.nix_store_paths)
      
      -- Should have path info
      assert.is_not_nil(result.nix_path_info)
      assert.is_not_nil(result.nix_path_info["/nix/store/abc123-hello-2.12.1"])
      assert.equals(12345, result.nix_path_info["/nix/store/abc123-hello-2.12.1"].narSize)
    end)

    it("should copy result to clipboard when requested", function()
      local component = nix_build_results_comp.constructor({
        copy_result_to_clipboard = true
      })
      
      component.build_results = { "/nix/store/abc123-hello-2.12.1" }
      
      -- Mock vim.fn.setreg
      local clipboard_content = nil
      local original_setreg = vim.fn.setreg
      vim.fn.setreg = function(register, content)
        if register == "+" then
          clipboard_content = content
        end
        return original_setreg(register, content)
      end
      
      local task = {}
      local result = {}
      
      component.on_result(component, task, result)
      
      -- Should have copied to clipboard
      assert.equals("/nix/store/abc123-hello-2.12.1", clipboard_content)
      
      -- Restore original function
      vim.fn.setreg = original_setreg
    end)
  end)

  describe("on_complete", function()
    it("should show notification for successful builds", function()
      local notifications = {}
      vim.notify = function(message, level, opts)
        table.insert(notifications, { message = message, level = level, opts = opts })
      end
      
      local component = nix_build_results_comp.constructor({
        result_notification = true
      })
      
      component.build_results = { "/nix/store/abc123-hello-2.12.1" }
      
      local task = { name = "test-task" }
      local result = {}
      
      component.on_complete(component, task, "SUCCESS", result)
      
      -- Should have shown notification
      assert.equals(1, #notifications)
      assert.is_true(notifications[1].message:find("Built:") ~= nil)
      assert.equals(vim.log.levels.INFO, notifications[1].level)
      assert.equals("Nix Build", notifications[1].opts.title)
    end)

    it("should show runtime dependencies when requested", function()
      local component = nix_build_results_comp.constructor({
        show_runtime_deps = true
      })
      
      component.build_results = { "/nix/store/abc123-hello-2.12.1" }
      
      -- Mock vim.system for nix path-info -r
      vim.system = function(cmd, opts)
        if cmd[1] == "nix" and cmd[2] == "path-info" and cmd[3] == "-r" then
          return {
            wait = function()
              return {
                code = 0,
                stdout = table.concat({
                  "/nix/store/abc123-hello-2.12.1",
                  "/nix/store/def456-glibc-2.38",
                  "/nix/store/ghi789-gcc-13.2.0"
                }, "\n"),
                stderr = ""
              }
            end
          }
        end
        return original_system(cmd, opts)
      end
      
      local task = { name = "test-task" }
      local result = {}
      
      component.on_complete(component, task, "SUCCESS", result)
      
      -- Function should complete without error
      -- Runtime deps are logged, which we can't easily test without mocking log
    end)
  end)

  describe("render", function()
    it("should display build results in detailed view", function()
      local component = nix_build_results_comp.constructor({
        show_build_paths = true
      })
      
      component.build_results = { 
        "/nix/store/abc123-hello-2.12.1",
        "/nix/store/def456-world-1.0"
      }
      
      local task = {}
      local lines = {}
      local highlights = {}
      
      component.render(component, task, lines, highlights, 2)
      
      -- Should display build results
      assert.has.truthy(vim.tbl_contains(lines, "Build Results (2):"))
      assert.has.truthy(vim.tbl_contains(lines, "  abc123-hello-2.12.1"))
      assert.has.truthy(vim.tbl_contains(lines, "  def456-world-1.0"))
    end)

    it("should show full paths in very detailed view", function()
      local component = nix_build_results_comp.constructor({
        show_build_paths = true
      })
      
      component.build_results = { "/nix/store/abc123-hello-2.12.1" }
      
      local task = {}
      local lines = {}
      local highlights = {}
      
      component.render(component, task, lines, highlights, 3)
      
      -- Should display full paths
      assert.has.truthy(vim.tbl_contains(lines, "    /nix/store/abc123-hello-2.12.1"))
    end)

    it("should limit display for many results", function()
      local component = nix_build_results_comp.constructor({
        show_build_paths = true
      })
      
      -- Create many build results
      component.build_results = {}
      for i = 1, 10 do
        table.insert(component.build_results, string.format("/nix/store/abc%03d-package-%d", i, i))
      end
      
      local task = {}
      local lines = {}
      local highlights = {}
      
      component.render(component, task, lines, highlights, 2)
      
      -- Should limit display and show "... and X more"
      local found_more_indicator = false
      for _, line in ipairs(lines) do
        if line:match("%.%.%. and %d+ more") then
          found_more_indicator = true
          break
        end
      end
      assert.is_true(found_more_indicator)
    end)
  end)
end)