#!/usr/bin/env lua

-- Debug script to test overseer color implementation
local overseer = require('overseer')

-- Setup overseer with debug
overseer.setup({
  task_list = {
    show_description = true,
    description_format = "%s (%s)"
  }
})

-- Check config
print("=== Config Check ===")
local config = require('overseer.config')
print("show_description:", config.task_list.show_description)
print("description_format:", config.task_list.description_format)

-- Check highlight groups
print("\n=== Highlight Groups ===")
local highlights = require('overseer.init').get_all_highlights()
for _, hl in ipairs(highlights) do
  if hl.name:match("OverseerTask") then
    print(string.format("%s -> %s (%s)", hl.name, hl.default, hl.desc))
  end
end

-- Try to create a task with description
print("\n=== Template Test ===")
local templates = require('overseer.template').list({dir = vim.fn.getcwd()})
for i, tmpl in ipairs(templates) do
  if i <= 3 then -- Show first 3 templates
    print(string.format("Template: %s | Desc: %s", tmpl.name, tmpl.desc or "NO DESC"))
  end
end

print("\n=== Task Creation Test ===")
-- Test creating a task with description
local task_def = {
  name = "test task",
  cmd = "echo hello",
  metadata = {
    desc = "This is a test description"
  }
}

local Task = require('overseer.task')
local task = Task.new(task_def)
print("Task name:", task.name)
print("Task metadata:", vim.inspect(task.metadata))

-- Test rendering
local lines = {}
local highlights = {}
task:render(lines, highlights, 1)
print("Rendered lines:", vim.inspect(lines))
print("Highlights:", vim.inspect(highlights))