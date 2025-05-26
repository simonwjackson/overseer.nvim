local nix_provider = require("overseer.template.nix")
local util = require("overseer.util")

describe("nix template provider", function()
  local test_dir
  local original_cwd

  before_each(function()
    original_cwd = vim.fn.getcwd()
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    vim.cmd("cd " .. test_dir)
  end)

  after_each(function()
    vim.cmd("cd " .. original_cwd)
    vim.fn.delete(test_dir, "rf")
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

    it("should return false when no flake.nix file is found", function()
      -- Assume nix is available
      local original_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "nix" then
          return 1
        end
        return original_executable(cmd)
      end

      local ok, err = nix_provider.condition.callback({ dir = test_dir })
      assert.is_false(ok)
      assert.equals("No flake.nix file found", err)

      -- Restore original function
      vim.fn.executable = original_executable
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

      -- Mock nix as available
      local original_executable = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "nix" then
          return 1
        end
        return original_executable(cmd)
      end

      local ok, err = nix_provider.condition.callback({ dir = test_dir })
      assert.is_true(ok)
      assert.is_nil(err)

      -- Restore original function
      vim.fn.executable = original_executable
    end)
  end)

  describe("cache_key", function()
    it("should return flake.nix path when present", function()
      -- Create flake.nix file
      local flake_path = test_dir .. "/flake.nix"
      local file = io.open(flake_path, "w")
      file:write("{ }")
      file:close()

      local cache_key = nix_provider.cache_key({ dir = test_dir })
      assert.equals(flake_path, cache_key)
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
      assert.equals(flake_path, cache_key)
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
  end)
end)