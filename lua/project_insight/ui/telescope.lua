---@module 'project_insight.ui.telescope'
---@brief Telescope picker for symbol index.
local M = {}

local notify = require("project_insight.util.notify").create("[project_insight.ui.telescope]")

---Open a telescope picker over the provided symbol entries.
---@param entries table[]   each has `.filename`, `.lnum`, `.name`, `.func_type`, `.language`
---@param title   string
function M.open(entries, title)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    notify.error("telescope.nvim is not installed")
    return
  end

  local finders      = require("telescope.finders")
  local conf         = require("telescope.config").values
  local actions      = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local action_layout= require("telescope.actions.layout")

  pickers.new({}, {
    prompt_title = title or "Project Symbols",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(e)
        -- Display: path:line  [type] name
        local display = string.format("%s:%d  [%s] %s",
          e.filename or "?", e.lnum or 0, e.func_type or "?", e.name or "?")
        return {
          value    = e,
          display  = display,
          ordinal  = (e.name or "") .. " " .. (e.filename or ""),
          filename = e.filename,
          lnum     = e.lnum,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<C-p>", action_layout.toggle_preview)
      map("n", "<C-p>", action_layout.toggle_preview)
      actions.select_default:replace(function()
        local sel = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.cmd("edit " .. vim.fn.fnameescape(sel.filename))
        vim.api.nvim_win_set_cursor(0, { sel.lnum, 0 })
      end)
      return true
    end,
  }):find()
end

return M
