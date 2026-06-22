---@module 'project_insight.scan.rg'
---@brief Ripgrep command builder and executor.
local M = {}

local notify = require("project_insight.util.notify").create("[project_insight.scan.rg]")

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

---Execute rg synchronously; returns (lines, exit_code).
---@param cmd string[]
---@return string[], integer
function M.exec_sync(cmd)
  local lines = vim.fn.systemlist(cmd)
  return lines, vim.v.shell_error
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
