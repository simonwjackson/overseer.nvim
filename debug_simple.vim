" Debug script for overseer colors
set rtp+=.

" Load overseer
lua require('overseer').setup({task_list = {show_description = true, description_format = "%s (%s)"}})

" Check config
lua print("=== Config ===")
lua local config = require('overseer.config')
lua print("show_description:", config.task_list.show_description)
lua print("description_format:", config.task_list.description_format)

" Check highlight groups are defined
lua print("=== Highlights ===")
highlight

" Try to run OverseerRun to see if descriptions show up
echo "Ready to test - try :OverseerRun to see if descriptions appear with colors"