---@module 'insights.scan.rg'
---@brief Ripgrep command builder and executor.
local M = {}

local notify = require("insights.util.notify").create("[insights.scan.rg]")

---Build rg --vimgrep command arguments.
---@param pattern string   PCRE2 pattern
---@param extensions string[]  e.g. {"lua", "py"}
---@param opts { cwd?: string, exclude_patterns?: string[], max_file_size_kb?: integer, follow_symlinks?: boolean }
---@return string[]
function M.build_cmd(pattern, extensions, opts)
  opts = opts or {}
  local cmd = { "rg", "--vimgrep", "--no-heading", "--pcre2" }

  for _, ext in ipairs(extensions) do
    cmd[#cmd + 1] = "--glob"
    cmd[#cmd + 1] = "*." .. ext
  end

  for _, excl in ipairs(opts.exclude_patterns or {}) do
    cmd[#cmd + 1] = "--glob"
    cmd[#cmd + 1] = "!" .. excl
  end

  if opts.max_file_size_kb and opts.max_file_size_kb > 0 then
    cmd[#cmd + 1] = "--max-filesize"
    cmd[#cmd + 1] = tostring(opts.max_file_size_kb) .. "K"
  end

  if opts.follow_symlinks then
    cmd[#cmd + 1] = "--follow"
  end

  cmd[#cmd + 1] = pattern
  cmd[#cmd + 1] = opts.cwd or "."

  return cmd
end

---How long a single rg invocation may take before it is given up on. A scan of
---a very large tree can legitimately take a while; this only exists so a wedged
---process can't hang the editor forever.
local TIMEOUT_MS = 120000

---Execute rg and wait for it; returns (lines, exit_code).
---
---Deliberately `vim.system` + `vim.wait` rather than `vim.fn.systemlist`, even
---though both block the caller and this function's signature is unchanged.
---`systemlist` blocks the event loop outright, which means nothing can be drawn
---while it runs — a progress indicator built on a `vim.uv` timer (as
---`lib.nvim.progress`'s delay guard is) never even fires. `vim.wait` pumps the
---loop instead, so timers run and `:redrawstatus` actually paints, which is what
---lets `symbols.rg_index` report progress from an otherwise synchronous build
---without every caller having to become callback-based.
---@param cmd string[]
---@return string[], integer
function M.exec_sync(cmd)
  local result = nil
  vim.system(cmd, { text = true }, function(res)
    result = res
  end)

  local completed = vim.wait(TIMEOUT_MS, function() return result ~= nil end, 10)
  if not completed or not result then
    return {}, -1
  end

  local out = result.stdout or ""
  if out == "" then
    return {}, result.code
  end
  -- `systemlist`'s contract: one entry per line, no trailing empty element.
  return vim.split(out:gsub("\r?\n$", ""), "\r?\n"), result.code
end

---Run one rg search and return lines; logs errors (exit != 0 and != 1).
---@param cmd string[]
---@param label string   e.g. language name for error messages
---@return string[]
function M.run(cmd, label)
  if vim.fn.executable("rg") ~= 1 then
    notify.error("ripgrep (rg) not found in PATH")
    return {}
  end
  local lines, code = M.exec_sync(cmd)
  if code == 0 then
    return lines
  elseif code == 1 then
    return {}  -- exit 1 = no matches, not an error
  else
    notify.debug(string.format("%s: rg exited %d", label or "rg", code))
    return {}
  end
end

return M
