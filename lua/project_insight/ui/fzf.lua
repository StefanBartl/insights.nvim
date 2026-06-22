---@module 'project_insight.ui.fzf'
---@brief fzf-lua picker for symbol index.
local M = {}

local notify = require("project_insight.util.notify").create("[project_insight.ui.fzf]")

---Open a fzf-lua picker over symbol entries.
---@param entries table[]
---@param title   string
function M.open(entries, title)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.error("fzf-lua is not installed")
    return
  end

  local lines = {}
  for _, e in ipairs(entries) do
    lines[#lines + 1] = string.format("%s:%d  [%s] %s",
      e.filename or "?", e.lnum or 0, e.func_type or "?", e.name or "?")
  end

  fzf.fzf_exec(lines, {
    prompt    = (title or "Project Symbols") .. "> ",
    previewer = "builtin",
    actions   = {
      ["default"] = function(sel)
        local file, lnum = sel[1]:match("^([^:]+):(%d+)")
        if file and lnum then
          vim.cmd("edit " .. vim.fn.fnameescape(file))
          vim.api.nvim_win_set_cursor(0, { tonumber(lnum), 0 })
        end
      end,
    },
    winopts = { preview = { default = "builtin" } },
  })
end

return M
