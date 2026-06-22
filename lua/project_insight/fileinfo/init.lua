---@module 'project_insight.fileinfo'
---@brief Floating window with filesystem metadata for the current buffer.
local M = {}

local uv        = vim.uv or vim.loop
local api       = vim.api
local str_fmt   = string.format
local os_date   = os.date
local bitlib    = require("bit")

local active_win  = nil
local active_path = nil

local function format_size(size)
  return str_fmt("%d bytes (%.2f MiB)", size, size / (1024 * 1024))
end

local function format_permissions(stat)
  local mode  = stat.mode or 0
  local octal = str_fmt("%o", mode)
  if vim.fn.has("win32") == 1 then
    return octal .. " (Windows / limited POSIX meaning)"
  end
  local perm = mode % 512
  local function bits(v)
    local map = { "r", "w", "x" }
    local s = ""
    for i = 2, 0, -1 do
      local b = 2 ^ i
      s = s .. (bitlib.band(v, b) ~= 0 and map[3 - i] or "-")
    end
    return s
  end
  local u = bits(math.floor(perm / 64))
  local g = bits(math.floor((perm % 64) / 8))
  local o = bits(perm % 8)
  return str_fmt("%s (POSIX %s %s %s)", octal, u, g, o)
end

local function close_active()
  if active_win and api.nvim_win_is_valid(active_win) then
    api.nvim_win_close(active_win, true)
  end
  active_win, active_path = nil, nil
end

local function open_hover(path, lines)
  -- Toggle: close if same path is already shown
  if active_win and api.nvim_win_is_valid(active_win) and active_path == path then
    close_active(); return
  end
  close_active()

  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })
  api.nvim_set_option_value("bufhidden",  "wipe", { buf = buf })

  local close_fn = function()
    if active_win and api.nvim_win_is_valid(active_win) then
      api.nvim_win_close(active_win, true)
      active_win, active_path = nil, nil
    end
  end
  vim.keymap.set("n", "q",     close_fn, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", close_fn, { buffer = buf, nowait = true })

  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, #l) end

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    style    = "minimal",
    border   = "rounded",
    width    = width + 2,
    height   = #lines,
    row      = 2,
    col      = math.floor((vim.o.columns - width) / 2),
  })

  active_win  = win
  active_path = path
end

---Show (or toggle) the file info float for the current buffer.
function M.show()
  local path = api.nvim_buf_get_name(0)
  if path == "" then
    open_hover("<buffer>", { "Current buffer has no associated file." })
    return
  end

  local stat = uv.fs_stat(path)
  if not stat then
    open_hover(path, { "No filesystem info available for: " .. path })
    return
  end

  open_hover(path, {
    "Path:        " .. path,
    "Type:        " .. stat.type,
    "Size:        " .. format_size(stat.size),
    "Permissions: " .. format_permissions(stat),
    "UID:         " .. tostring(stat.uid or "n/a"),
    "GID:         " .. tostring(stat.gid or "n/a"),
    "Accessed:    " .. os_date("%Y-%m-%d %H:%M:%S", stat.atime.sec),
    "Modified:    " .. os_date("%Y-%m-%d %H:%M:%S", stat.mtime.sec),
    "Changed:     " .. os_date("%Y-%m-%d %H:%M:%S", stat.ctime.sec),
  })
end

return M
