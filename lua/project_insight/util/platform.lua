---@module 'project_insight.util.platform'
local M = {}

function M.is_windows()
  return require("lib.nvim.cross.platform.is_windows")()
end

---@param parts string[]
---@return string
function M.joinpath(parts)
  local sep = M.is_windows() and "\\" or "/"
  return table.concat(parts, sep)
end

---Run a shell command asynchronously.
---Callback receives (success: boolean, stdout: string, stderr: string).
---@param cmd string
---@param cb fun(success: boolean, stdout: string, stderr: string)
function M.run_shell(cmd, cb)
  -- This module's own shell-selection (powershell on Windows, sh -c
  -- elsewhere) duplicated lib.nvim.cross.run.shell()/run() exactly.
  require("lib.nvim.cross.run").run(cmd, function(ok, res)
    cb(ok, res.stdout or "", res.stderr or "")
  end)
end

---Copy text to system clipboard; returns true on success.
---@param text string
---@return boolean
function M.copy_to_clipboard(text)
  return require("lib.nvim.cross.copy_to_clipboard")(text)
end

return M
