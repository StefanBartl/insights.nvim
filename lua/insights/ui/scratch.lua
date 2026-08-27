---@module 'insights.ui.scratch'
---@brief Display content in a read-only scratch buffer.
local M = {}

local api = vim.api
local map = require("lib.nvim.bindings.keymap")
local window = require("lib.nvim.window")
local kit = require("lib.nvim.ui.kit")
local notify = require("insights.util.notify").create("[insights.ui.scratch]")

---@internal
---Can `win` host the scratch buffer? True for a normal editing window
---(buftype "") or a window already showing one of our scratch buffers — but
---never a floating window or a special sidebar (neo-tree, qf, help, terminal).
---@param win integer
---@return boolean
local function is_usable_window(win)
  local wcfg = api.nvim_win_get_config(win)
  if wcfg and wcfg.relative and wcfg.relative ~= "" then
    return false
  end -- floating
  local b = api.nvim_win_get_buf(win)
  local bt = api.nvim_get_option_value("buftype", { buf = b })
  if bt == "" then
    return true
  end
  local ok, marked = pcall(api.nvim_buf_get_var, b, "insights_scratch")
  return ok and marked == true
end

---@internal
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

---Extra buffer-local keymap to install in a scratch buffer.
---@class ScratchKeymap
---@field [1] string         mode
---@field [2] string         lhs
---@field [3] string|function rhs
---@field desc string|nil

---@internal
---Read-only cheatsheet of every key bound on this scratch buffer — the
---fixed close/follow keys plus whatever the caller passed via `opts.keymaps`.
---@param title string|nil
---@param rows { lhs: string, desc: string }[]
---@return nil
local function show_help(title, rows)
  local widest = #"?"
  for _, r in ipairs(rows) do
    widest = math.max(widest, #r.lhs)
  end

  local lines = { "", (" %s keys"):format(title or "Insights"), "" }
  local function row(lhs, desc)
    lines[#lines + 1] = ("  %-" .. widest .. "s   %s"):format(lhs, desc)
  end
  for _, r in ipairs(rows) do
    row(r.lhs, r.desc)
  end
  row("?", "Show this help")
  lines[#lines + 1] = ""

  local width = 40
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  kit.viewer({
    lines = lines,
    title = (title or "Insights") .. " Keys",
    filetype = "insights-scratch-help",
    width = math.min(width + 2, math.floor(vim.o.columns * 0.9)),
    height = math.min(#lines, math.floor(vim.o.lines * 0.8)),
  })
end

---Open a scratch buffer containing `lines`, closing on `q` / `<Esc>`.
---@param lines string[]
---@param title string|nil
---@param opts { keymaps: ScratchKeymap[]|nil }|nil   extra buffer-local keymaps
---@return integer|nil bufnr
function M.open(lines, title, opts)
  if not lines or #lines == 0 then
    notify.warn("nothing to display")
    return
  end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  api.nvim_set_option_value("swapfile", false, { buf = buf })
  api.nvim_buf_set_var(buf, "insights_scratch", true)

  if title then
    pcall(api.nvim_buf_set_name, buf, "insights://" .. title)
  end

  -- Display in a normal window; never replace a sidebar's buffer (neo-tree
  -- would misread the buffer name as a path, and BufEnter-driven plugins can
  -- error on the transient buffer id).
  local win = target_window()
  api.nvim_win_set_buf(win, buf)

  local ui_cfg = require("insights.config").get().ui or {}
  local km = { noremap = true, silent = true, buffer = buf }
  local close_keys = ui_cfg.close_keys or { "q", "<Esc>" }
  window.nice_quit(win, { keys = close_keys })

  local help_rows = { { lhs = table.concat(close_keys, ", "), desc = "Close" } }

  if ui_cfg.follow_key and ui_cfg.follow_key ~= false then
    map("n", ui_cfg.follow_key, function()
      local line = api.nvim_get_current_line()
      -- Try to open path:line from current line
      local file, lnum = line:match("^([^:]+):(%d+)")
      if file then
        vim.cmd("edit " .. vim.fn.fnameescape(file))
        if lnum then
          api.nvim_win_set_cursor(0, { tonumber(lnum), 0 })
        end
      end
    end, km, "insights: follow path:line")
    help_rows[#help_rows + 1] = { lhs = ui_cfg.follow_key, desc = "Follow path:line under cursor" }
  end

  -- Caller-supplied buffer-local keymaps (e.g. imports' "go to definition").
  if opts and opts.keymaps then
    for _, m in ipairs(opts.keymaps) do
      map(m[1], m[2], m[3], { noremap = true, silent = true, buffer = buf }, m.desc)
      help_rows[#help_rows + 1] = { lhs = m[2], desc = m.desc or "" }
    end
  end

  map("n", "?", function()
    show_help(title, help_rows)
  end, km, "insights: show keymap cheatsheet")

  return buf
end

return M
