local Task = require("overseer.task")
local config = require("overseer.config")

describe("Backward compatibility", function()
  local original_config

  before_each(function()
    -- Save original config
    original_config = vim.deepcopy(config.task_list)
  end)

  after_each(function()
    -- Restore original config
    config.task_list = original_config
  end)

  describe("Task rendering with descriptions disabled (default)", function()
    before_each(function()
      config.task_list.show_description = false
    end)

    it("should render task without description using original OverseerTask highlight", function()
      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        components = {}, -- No components for simpler test
      })
      task.status = "RUNNING"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Should have the status and task name
      assert.equals(1, #lines)
      assert.equals("RUNNING: test_task", lines[1])

      -- Should have status highlight and original task highlight
      assert.equals(2, #highlights)
      assert.equals("OverseerRUNNING", highlights[1][1])
      assert.equals("OverseerTask", highlights[2][1]) -- Original highlight group
    end)

    it("should render task with description metadata but ignore it when disabled", function()
      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        metadata = { desc = "Test description" },
        components = {}, -- No components for simpler test
      })
      task.status = "SUCCESS"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Should still render without description
      assert.equals(1, #lines)
      assert.equals("SUCCESS: test_task", lines[1])

      -- Should use original highlight group
      assert.equals(2, #highlights)
      assert.equals("OverseerSUCCESS", highlights[1][1])
      assert.equals("OverseerTask", highlights[2][1])
    end)
  end)

  describe("Task rendering with descriptions enabled", function()
    before_each(function()
      config.task_list.show_description = true
    end)

    it("should render task with description using new highlight groups", function()
      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        metadata = { desc = "Test description" },
        components = {}, -- No components for simpler test
      })
      task.status = "RUNNING"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Should have formatted display with description
      assert.equals(1, #lines)
      assert.equals("RUNNING: test_task (Test description)", lines[1])

      -- Should have separate highlights for name and description
      assert.equals(3, #highlights)
      assert.equals("OverseerRUNNING", highlights[1][1]) -- Status
      assert.equals("OverseerTaskName", highlights[2][1]) -- Task name
      assert.equals("OverseerTaskDesc", highlights[3][1]) -- Description
    end)

    it("should fallback to original rendering for tasks without description", function()
      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        components = {}, -- No components for simpler test
      })
      task.status = "PENDING"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Should render normally without description
      assert.equals(1, #lines)
      assert.equals("PENDING: test_task", lines[1])

      -- Should use original highlight group when no description
      assert.equals(2, #highlights)
      assert.equals("OverseerPENDING", highlights[1][1])
      assert.equals("OverseerTask", highlights[2][1])
    end)

    it("should use custom description format when configured", function()
      config.task_list.description_format = "%s - %s"

      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        metadata = { desc = "Custom desc" },
        components = {}, -- No components for simpler test
      })
      task.status = "RUNNING"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Should use custom format
      assert.equals(1, #lines)
      assert.equals("RUNNING: test_task - Custom desc", lines[1])
    end)
  end)

  describe("Configuration defaults", function()
    it("should have show_description disabled by default for backward compatibility", function()
      local default_config = require("overseer.config")
      assert.equals(false, default_config.task_list.show_description)
    end)

    it("should have sensible default description format", function()
      local default_config = require("overseer.config")
      assert.equals("%s (%s)", default_config.task_list.description_format)
    end)
  end)

  describe("Edge cases", function()
    before_each(function()
      config.task_list.show_description = true
    end)

    it("should handle empty description gracefully", function()
      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        metadata = { desc = "" },
        components = {}, -- No components for simpler test
      })
      task.status = "SUCCESS"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Empty description should still be displayed
      assert.equals(1, #lines)
      assert.equals("SUCCESS: test_task ()", lines[1])
    end)

    it("should handle nil metadata gracefully", function()
      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        metadata = nil,
        components = {}, -- No components for simpler test
      })
      task.status = "FAILURE"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Should fall back to original rendering
      assert.equals(1, #lines)
      assert.equals("FAILURE: test_task", lines[1])
      assert.equals("OverseerTask", highlights[2][1])
    end)

    it("should handle metadata without desc field", function()
      local task = Task.new({
        name = "test_task",
        cmd = { "echo", "hello" },
        metadata = { other_field = "value" },
        components = {}, -- No components for simpler test
      })
      task.status = "RUNNING"

      local lines = {}
      local highlights = {}
      task:render(lines, highlights, 1)

      -- Should fall back to original rendering
      assert.equals(1, #lines)
      assert.equals("RUNNING: test_task", lines[1])
      assert.equals("OverseerTask", highlights[2][1])
    end)
  end)
end)