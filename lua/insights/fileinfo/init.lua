---@module 'insights.fileinfo'
---@brief Floating window with filesystem metadata for the current buffer.
local M = {}

local uv        = vim.uv or vim.loop
local api       = vim.api
local str_fmt   = string.format
local os_date   = os.date
local bitlib    = require("bit")
local make_scratch = require("lib.nvim.window.make_scratch")

local active_win  = nil
local active_path = nil

local function format_size(size)
  return str_fmt("%d bytes (%.2f MiB)", size, size / (1024 * 1024))
end

local function format_permissions(stat)
  local mode  = stat.mode or 0
  local octal = str_fmt("%o", mode)
  if require("insights.util.platform").is_windows() then
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

  local close_keys = (require("insights.config").get().ui or {}).close_keys or { "q", "<Esc>" }

  -- width/height are left to make_scratch's defaults: content_width(lines)+2
  -- and #lines, matching this function's own former width+2/#lines exactly.
  -- row=2 (near the top, not vertically centered) is passed explicitly since
  -- that's this float's own deliberate positioning, not make_scratch's
  -- default (which centers vertically).
  local win = make_scratch({
    lines = lines,
    row = 2,
    nice_quit = { keys = close_keys },
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
