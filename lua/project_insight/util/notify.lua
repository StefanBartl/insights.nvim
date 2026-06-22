---@module 'project_insight.util.notify'
local M = {}

---@param prefix string
---@return { info: fun(msg:string), warn: fun(msg:string), error: fun(msg:string), debug: fun(msg:string) }
function M.create(prefix)
  local function notify(msg, level)
    vim.notify(prefix .. " " .. msg, level)
  end
  return {
    info  = function(msg) notify(msg, vim.log.levels.INFO) end,
    warn  = function(msg) notify(msg, vim.log.levels.WARN) end,
    error = function(msg) notify(msg, vim.log.levels.ERROR) end,
    debug = function(msg)
      if vim.g.project_insight_debug then
        notify(msg, vim.log.levels.DEBUG)
      end
    end,
  }
end

return M
