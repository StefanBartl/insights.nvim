---@module 'insights.util.platform'
--- Cross-platform helpers: OS detection, path joining, shell execution and
--- clipboard access, delegating to lib.nvim where available.
local M = {}

---@return boolean
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
---
---`cb` runs on the main loop, so `vim.fn.*`, `vim.api.*` and `vim.notify` are
---all safe inside it. `vim.system` delivers its own callback in a fast event
---context, where those raise "must not be called in a fast event context" --
---and every consumer here ends in a notify, which is exactly that. Scheduling
---once in the one place beats each caller remembering.
---@param cmd string
---@param cb fun(success: boolean, stdout: string, stderr: string)
function M.run_shell(cmd, cb)
  -- This module's own shell-selection (powershell on Windows, sh -c
  -- elsewhere) duplicated lib.nvim.cross.run.shell()/run() exactly.
  require("lib.nvim.cross.run").run(cmd, function(ok, res)
    local stdout, stderr = res.stdout or "", res.stderr or ""
    vim.schedule(function()
      cb(ok, stdout, stderr)
    end)
  end)
end

---Copy text to system clipboard; returns true on success.
---@param text string
---@return boolean
function M.copy_to_clipboard(text)
  return require("lib.nvim.cross.copy_to_clipboard")(text)
end

return M
