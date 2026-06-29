---@module 'project_insight.ui.scratch'
---@brief Display content in a read-only scratch buffer.
local M = {}

local api = vim.api

---Can `win` host the scratch buffer? True for a normal editing window
---(buftype "") or a window already showing one of our scratch buffers — but
---never a floating window or a special sidebar (neo-tree, qf, help, terminal).
---@param win integer
---@return boolean
local function is_usable_window(win)
  local wcfg = api.nvim_win_get_config(win)
  if wcfg and wcfg.relative and wcfg.relative ~= "" then return false end  -- floating
  local b  = api.nvim_win_get_buf(win)
  local bt = api.nvim_get_option_value("buftype", { buf = b })
  if bt == "" then return true end
  local ok, marked = pcall(api.nvim_buf_get_var, b, "project_insight_scratch")
  return ok and marked == true
end

---Find a window to display the scratch buffer in, opening a split if the
---current window is a sidebar (so we never hijack neo-tree etc.).
---@return integer win
local function target_window()
  if is_usable_window(api.nvim_get_current_win()) then
    return api.nvim_get_current_win()
  end
  for _, w in ipairs(api.nvim_list_wins()) do
    if is_usable_window(w) then
      api.nvim_set_current_win(w)
      return w
    end
  end
  vim.cmd("botright split")
  return api.nvim_get_current_win()
end

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
  api.nvim_buf_set_var(buf, "project_insight_scratch", true)

  if title then
    pcall(api.nvim_buf_set_name, buf, "project-insight://" .. title)
  end

  -- Display in a normal window; never replace a sidebar's buffer (neo-tree
  -- would misread the buffer name as a path, and BufEnter-driven plugins can
  -- error on the transient buffer id).
  local win = target_window()
  api.nvim_win_set_buf(win, buf)

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
