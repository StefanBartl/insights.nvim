---@module 'project_insight.config'
--- Merges user options (from setup()) over the plugin's defaults.
--- See config/DEFAULTS.lua for the default values and config/@types for
--- their types.

require("project_insight.config.@types")

local M = {}

---@type ProjectInsightConfig
local defaults = require("project_insight.config.DEFAULTS")

---@type ProjectInsightConfig
local current = vim.deepcopy(defaults)

---@param opts ProjectInsightConfig|nil
function M.setup(opts)
  current = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@return ProjectInsightConfig
function M.get()
  return current
end

return M
