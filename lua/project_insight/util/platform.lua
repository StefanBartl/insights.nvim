---@module 'project_insight.util.platform'
local M = {}

function M.is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

---@param parts string[]
---@return string
function M.joinpath(parts)
  local sep = M.is_windows() and "\\" or "/"
  return table.concat(parts, sep)
end

---Run a shell command asynchronously (vim.system, Neovim 0.10+).
---Callback receives (success: boolean, stdout: string, stderr: string).
---@param cmd string
---@param cb fun(success: boolean, stdout: string, stderr: string)
function M.run_shell(cmd, cb)
  local args = M.is_windows()
    and { "powershell", "-NonInteractive", "-Command", cmd }
    or  { "sh", "-c", cmd }
  vim.system(args, { text = true }, function(result)
    local ok = result.code == 0
    vim.schedule(function()
      cb(ok, result.stdout or "", result.stderr or "")
    end)
  end)
end

---Copy text to system clipboard; returns true on success.
---@param text string
---@return boolean
function M.copy_to_clipboard(text)
  if pcall(vim.fn.setreg, "+", text) then return true end
  return pcall(vim.fn.setreg, "*", text)
end

return M
