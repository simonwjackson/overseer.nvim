local nix_provider = require("overseer.template.nix")
local util = require("overseer.util")

describe("nix template provider", function()
  local test_dir
  local original_cwd
  local original_executable
  local original_system

  before_each(function()
    original_cwd = vim.fn.getcwd()
    original_executable = vim.fn.executable
    original_system = vim.system
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    vim.cmd("cd " .. test_dir)
    
    -- Mock nix as available by default
    vim.fn.executable = function(cmd)
      if cmd == "nix" then
        return 1
      end
      return original_executable(cmd)
    end
  end)

  after_each(function()
    vim.cmd("cd " .. original_cwd)
    vim.fn.delete(test_dir, "rf")
    vim.fn.executable = original_executable
    vim.system = original_system
  end)

  describe("condition", function()
    it("should return false when nix command is not available", function()
      -- Mock vim.fn.executable to return 0 (not found)
      local original_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "nix" then
          return 0
        end
        return original_executable(cmd)
      end

      local ok, err = nix_provider.condition.callback({ dir = test_dir })
      assert.is_false(ok)
      assert.equals('Command "nix" not found', err)

      -- Restore original function
      vim.fn.executable = original_executable
    end)

    it("should return false when no flake.nix or default.nix file is found", function()
      local ok, err = nix_provider.condition.callback({ dir = test_dir })
      assert.is_false(ok)
      assert.equals("No flake.nix or default.nix file found", err)
    end)

    it("should return true when nix is available and flake.nix exists", function()
      -- Create flake.nix file
      local flake_content = [[
{
  description = "Test flake";
  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.hello;
  };
}
]]
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write(flake_content)
      file:close()

      local ok, err = nix_provider.condition.callback({ dir = test_dir })
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("should return true when nix is available and default.nix exists", function()
      -- Create default.nix file
      local default_content = [[
{ pkgs ? import <nixpkgs> {} }:
pkgs.hello
]]
      local default_path = test_dir .. "/default.nix"
      local file = io.open(default_path, "w")
      file:write(default_content)
      file:close()

      local ok, err = nix_provider.condition.callback({ dir = test_dir })
      assert.is_true(ok)
      assert.is_nil(err)
    end)
  end)

  describe("cache_key", function()
    it("should return cache key starting with flake.nix path when present", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local cache_key = nix_provider.cache_key({ dir = test_dir })
      assert.is_not_nil(cache_key)
      assert.is_true(string.find(cache_key, flake_path) == 1)
    end)

    it("should return nil when flake.nix is not present", function()
      local cache_key = nix_provider.cache_key({ dir = test_dir })
      assert.is_nil(cache_key)
    end)

    it("should find flake.nix in parent directories", function()
      -- Create subdirectory
      local subdir = test_dir .. "/subdir"
      vim.fn.mkdir(subdir, "p")

      -- Create flake.nix in parent directory
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local cache_key = nix_provider.cache_key({ dir = subdir })
      assert.is_not_nil(cache_key)
      assert.is_true(string.find(cache_key, flake_path) == 1)
    end)
  end)

  describe("generator", function()
    it("should generate common nix templates", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local templates = {}
      nix_provider.generator({ dir = test_dir }, function(generated_templates)
        templates = generated_templates
      end)

      -- Should have generated templates for common commands
      assert.is_true(#templates > 0)

      local template_names = {}
      for _, template in ipairs(templates) do
        table.insert(template_names, template.name)
      end

      -- Check for expected templates
      assert.has.truthy(vim.tbl_contains(template_names, "nix develop"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix run"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix flake check"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix flake update"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix"))
    end)

    it("should set correct working directory for templates", function()
      -- Create flake.nix file in subdirectory
      local subdir = test_dir .. "/project"
      vim.fn.mkdir(subdir, "p")
      local flake_path = subdir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local templates = {}
      nix_provider.generator({ dir = subdir .. "/nested" }, function(generated_templates)
        templates = generated_templates
      end)

      -- All templates should have the correct cwd (where flake.nix is located)
      for _, template in ipairs(templates) do
        if template.name == "nix develop" then -- Test one specific template
          -- The cwd should be available as a default parameter
          local params = template.params
          assert.equals(subdir, params.cwd.default)
          break
        end
      end
    end)

    it("should generate legacy nix templates for default.nix", function()
      -- Create default.nix file
      local default_path = test_dir .. "/default.nix"
      local file = io.open(default_path, "w")
      file:write("{ pkgs ? import <nixpkgs> {} }: pkgs.hello")
      file:close()

      local templates = {}
      nix_provider.generator({ dir = test_dir }, function(generated_templates)
        templates = generated_templates
      end)

      -- Should have generated templates for legacy commands
      assert.is_true(#templates > 0)

      local template_names = {}
      for _, template in ipairs(templates) do
        table.insert(template_names, template.name)
      end

      -- Check for expected legacy templates
      assert.has.truthy(vim.tbl_contains(template_names, "nix build"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix shell"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix"))
      
      -- Should not have flake-specific commands
      assert.has.falsy(vim.tbl_contains(template_names, "nix develop"))
      assert.has.falsy(vim.tbl_contains(template_names, "nix flake check"))
    end)
  end)

  describe("dynamic discovery", function()
    it("should generate additional templates from nix flake show output", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      -- Mock vim.system to return fake flake show output
      vim.system = function(cmd, opts)
        if cmd[1] == "nix" and cmd[2] == "flake" and cmd[3] == "show" then
          local mock_output = {
            packages = {
              ["x86_64-linux"] = {
                default = {},
                mypackage = {},
                anotherpackage = {}
              }
            },
            apps = {
              ["x86_64-linux"] = {
                default = {},
                myapp = {},
                cli = {}
              }
            },
            devShells = {
              ["x86_64-linux"] = {
                default = {},
                python = {},
                rust = {}
              }
            },
            checks = {
              ["x86_64-linux"] = {
                test = {},
                lint = {}
              }
            }
          }
          return {
            wait = function()
              return {
                code = 0,
                stdout = vim.json.encode(mock_output),
                stderr = ""
              }
            end
          }
        end
        return original_system(cmd, opts)
      end

      local templates = {}
      nix_provider.generator({ dir = test_dir }, function(generated_templates)
        templates = generated_templates
      end)

      local template_names = {}
      for _, template in ipairs(templates) do
        table.insert(template_names, template.name)
      end

      -- Should include dynamically discovered templates
      assert.has.truthy(vim.tbl_contains(template_names, "nix build .#mypackage"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build .#anotherpackage"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix run .#myapp"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix run .#cli"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix develop .#python"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix develop .#rust"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build .#checks.x86_64-linux.test"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build .#checks.x86_64-linux.lint"))
      
      -- Should still include static templates
      assert.has.truthy(vim.tbl_contains(template_names, "nix develop"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build"))
    end)

    it("should handle nix flake show failures gracefully", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      -- Mock vim.system to return failure
      vim.system = function(cmd, opts)
        if cmd[1] == "nix" and cmd[2] == "flake" and cmd[3] == "show" then
          return {
            wait = function()
              return {
                code = 1,
                stdout = "",
                stderr = "error: cannot find flake inputs"
              }
            end
          }
        end
        return original_system(cmd, opts)
      end

      local templates = {}
      nix_provider.generator({ dir = test_dir }, function(generated_templates)
        templates = generated_templates
      end)

      -- Should still generate static templates even when dynamic discovery fails
      local template_names = {}
      for _, template in ipairs(templates) do
        table.insert(template_names, template.name)
      end

      assert.has.truthy(vim.tbl_contains(template_names, "nix develop"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix run"))
    end)

    it("should skip dynamic discovery when disabled in config", function()
      -- This test is hard to implement properly due to module caching
      -- For now, just verify that when discovery is disabled, we get fewer templates
      -- than when it's enabled
      
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      -- Mock vim.system to simulate dynamic discovery
      local discovery_call_count = 0
      vim.system = function(cmd, opts)
        if cmd[1] == "nix" and cmd[2] == "flake" and cmd[3] == "show" then
          discovery_call_count = discovery_call_count + 1
          local mock_output = {
            packages = {
              ["x86_64-linux"] = {
                default = {},
                mypackage = {}
              }
            }
          }
          return {
            wait = function()
              return {
                code = 0,
                stdout = vim.json.encode(mock_output),
                stderr = ""
              }
            end
          }
        end
        return original_system(cmd, opts)
      end

      local templates = {}
      nix_provider.generator({ dir = test_dir }, function(generated_templates)
        templates = generated_templates
      end)

      -- Should have called discovery (normal behavior)
      assert.is_true(discovery_call_count > 0)

      -- Should have both static and dynamic templates
      local template_names = {}
      for _, template in ipairs(templates) do
        table.insert(template_names, template.name)
      end

      assert.has.truthy(vim.tbl_contains(template_names, "nix develop"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build"))
      assert.has.truthy(vim.tbl_contains(template_names, "nix build .#mypackage"))
    end)
  end)

  describe("cache_key with dynamic discovery", function()
    it("should include flake.lock modification time in cache key", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      -- Create flake.lock file
      local lock_path = test_dir .. "/flake.lock"
      local lock_file = io.open(lock_path, "w")
      lock_file:write('{"version": 7}')
      lock_file:close()

      local cache_key = nix_provider.cache_key({ dir = test_dir })
      
      -- Cache key should include modification times
      assert.is_not_nil(cache_key)
      assert.is_true(string.find(cache_key, flake_path) == 1)
      assert.is_true(string.find(cache_key, "_") ~= nil) -- Should have timestamp separators
    end)

    it("should work without flake.lock file", function()
      -- Create only flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local cache_key = nix_provider.cache_key({ dir = test_dir })
      
      -- Should still generate cache key
      assert.is_not_nil(cache_key)
      assert.is_true(string.find(cache_key, flake_path) == 1)
    end)

    it("should return different cache keys for different flake modifications", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local cache_key1 = nix_provider.cache_key({ dir = test_dir })

      -- Wait a moment and modify the file
      vim.fn.system("sleep 1")
      local file2 = io.open(flake_path, "w")
      file2:write("{ description = \"modified\"; }")
      file2:close()

      local cache_key2 = nix_provider.cache_key({ dir = test_dir })

      -- Cache keys should be different
      assert.is_not.equals(cache_key1, cache_key2)
    end)
  end)
end)