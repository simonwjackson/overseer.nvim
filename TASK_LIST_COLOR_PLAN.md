# Task List Color Enhancement Plan

## Problem Statement

Currently, the task list displays entries in uniform white color, making it difficult to scan and differentiate between task names and descriptions. For example:

```
just build::default (Show available build recipes)
just build::frontend (Build frontend for production)
just dev::all (Start full development environment)
```

The goal is to make the task name more prominent and the description more opaque for better readability.

## Current Architecture Analysis

### Task Display Flow

1. **Template Selection** (`/lua/overseer/commands.lua:320-326`):
   - When users run `:OverseerRun`, templates are displayed via `vim.ui.select`
   - Format: `string.format("%s (%s)", tmpl.name, tmpl.desc)` if description exists
   - This creates the `"name (description)"` format the user sees

2. **Task Rendering** (`/lua/overseer/task.lua:163-232`):
   - Task:render method formats as: `"STATUS: task_name"`
   - Uses highlight groups: `"Overseer" .. self.status` for status, `"OverseerTask"` for name
   - **Important**: Task descriptions are NOT included in the task name stored in `self.name`

3. **Task List Display** (`/lua/overseer/task_list/sidebar.lua:356-453`):
   - Calls `task:render(lines, highlights, detail)` for each task
   - The task name in the list comes from `self.name`, not the template display format

### Current Highlight Groups

| Group                | Default Link     | Usage                    |
| -------------------- | ---------------- | ------------------------ |
| `OverseerTask`       | `Title`          | Task names               |
| `OverseerTaskBorder` | `FloatBorder`    | Separators               |
| `OverseerComponent`  | `Constant`       | Component names          |
| `Comment`            | `Comment`        | Component descriptions   |

## Root Issue Discovery

**Critical Finding**: The `"name (description)"` format only appears in the template selection UI (`vim.ui.select`), NOT in the actual task list display!

The task list shows the actual task names (like `"just build::default"`), and the descriptions are NOT part of the task name stored in the task object. The parenthetical descriptions the user sees are likely from:

1. The template selection phase
2. Component rendering (lines 190-193 in task.lua show `comp.name (comp.desc)` format)

## Solution Strategy

Since the task names themselves don't contain descriptions, we need to approach this differently:

### Option 1: Enhanced Template Selection Display (Immediate)

Enhance the `vim.ui.select` template picker with better highlighting:

1. **Location**: `/lua/overseer/commands.lua:317-332`
2. **Approach**: Modify the `format_item` function to return structured data that ui implementations can style
3. **Implementation**: Add highlight information to the selection items

### Option 2: Template Description Storage (Medium-term)

Store template descriptions in task metadata and display them in the task list:

1. **Storage**: Modify task creation to store original template description in `task.metadata.template_desc`
2. **Display**: Modify `Task:render` to include description with different highlighting
3. **Highlight**: Add new highlight group `OverseerTaskDesc` for descriptions

### Option 3: Custom Task List Renderer (Long-term)

Create a custom renderer that can parse and highlight task names containing descriptions:

1. **Parse**: Extract name and description from existing task names if they contain parentheses
2. **Render**: Apply different highlights to each part
3. **Configure**: Allow users to customize the formatting

## Recommended Implementation Plan

### Phase 1: New Highlight Groups

Add new highlight groups for better task name differentiation:

```lua
-- In /lua/overseer/init.lua get_all_highlights()
{ name = "OverseerTaskName", default = "Title", desc = "Primary task name" },
{ name = "OverseerTaskDesc", default = "Comment", desc = "Task description" },
```

### Phase 2: Enhanced Task Rendering

Modify the `Task:render` method to support description display:

1. **Store Description**: During task creation, store template description in metadata
2. **Render with Description**: If description exists, render as `"name (description)"`
3. **Apply Highlights**: Use `OverseerTaskName` for name, `OverseerTaskDesc` for description

### Phase 3: Template Integration

Update template providers to ensure descriptions are properly passed through:

NOTE: We should never arbitrarily add descriptions. If a template entry doesn't have a description, we should not add one.

1. **Template Building**: Modify `template.build_task_args` to include description in task metadata
2. **Task Creation**: Update `Task.new` to accept and store template descriptions

### Phase 4: Backward Compatibility

Ensure existing functionality remains intact:

1. **Fallback**: If no description, render normally with `OverseerTask` highlight
2. **Configuration**: Allow users to disable description display via config
3. **Testing**: Verify all template providers work correctly

## Technical Implementation Details

### File Changes Required

1. **`/lua/overseer/init.lua`**:
   - Add `OverseerTaskName` and `OverseerTaskDesc` highlight groups

2. **`/lua/overseer/task.lua`**:
   - Modify `Task:render` to handle descriptions
   - Update `Task.new` to accept template descriptions

3. **`/lua/overseer/template/init.lua`**:
   - Modify `build_task_args` to include description in task metadata

4. **`/lua/overseer/commands.lua`**:
   - Update template handling to pass descriptions through

### Configuration Options

Add new config options for users:

```lua
task_list = {
  -- Show template descriptions in task names
  show_description = true,
  -- Format for name + description
  description_format = "%s (%s)", -- name, desc
}
```

### Benefits

1. **Improved Readability**: Clear visual distinction between names and descriptions
2. **Consistent**: Works across all templates and task types
3. **Configurable**: Users can customize or disable the feature
4. **Backward Compatible**: Existing setups continue to work
5. **Extensible**: Foundation for future task list enhancements

## Testing Strategy

1. **Template Coverage**: Test with all built-in templates (just, npm, make, etc.)
2. **Description Handling**: Test tasks with and without descriptions
3. **Highlight Groups**: Verify colors work with various colorschemes
4. **Performance**: Ensure no significant performance impact
5. **Edge Cases**: Test long names/descriptions, special characters

This plan provides a comprehensive approach to adding color support to the task list while maintaining backward compatibility and setting up for future enhancements.
