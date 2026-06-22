---@module 'project_insight.ui.scratch'
---@brief Display content in a read-only scratch buffer.
local M = {}

local api = vim.api

---Open a scratch buffer containing `lines`, closing on `q` / `<Esc>`.
---@param lines string[]
---@param title string|nil
function M.open(lines, title)
  if not lines or #lines == 0 then
    vim.notify("[project-insight] nothing to display", vim.log.levels.WARN)
    return
  end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("buftype",    "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden",  "wipe", { buf = buf })
  api.nvim_set_option_value("swapfile",   false, { buf = buf })

  if title then
    pcall(api.nvim_buf_set_name, buf, "project-insight://" .. title)
  end

  api.nvim_set_current_buf(buf)

  local km = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set("n", "q",     "<cmd>bd!<cr>", km)
  vim.keymap.set("n", "<Esc>", "<cmd>bd!<cr>", km)
  vim.keymap.set("n", "gf", function()
    local line = api.nvim_get_current_line()
    -- Try to open path:line from current line
    local file, lnum = line:match("^([^:]+):(%d+)")
    if file then
      vim.cmd("edit " .. vim.fn.fnameescape(file))
      if lnum then
        api.nvim_win_set_cursor(0, { tonumber(lnum), 0 })
      end
    end
  end, km)
end

return M
