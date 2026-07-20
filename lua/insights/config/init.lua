---@module 'insights.config'
--- Merges user options (from setup()) over the plugin's defaults.
--- See config/DEFAULTS.lua for the default values and config/@types for
--- their types.

require("insights.config.@types")

local expand_path = require("lib.nvim.cross.fs.expand_path")

local M = {}

---@type InsightsConfig
local defaults = require("insights.config.DEFAULTS")

---@type InsightsConfig
local current = vim.deepcopy(defaults)

--- Expand `~`/`$VAR`/`%VAR%` in the handful of user-configurable path fields.
--- Defaults come from vim.fn.stdpath() and are already absolute, but
--- expand_path is a no-op on paths without env references, so running it
--- unconditionally is safe.
---@param cfg InsightsConfig
local function expand_paths(cfg)
  cfg.symbols.cache.dir = expand_path(cfg.symbols.cache.dir)
  cfg.metrics.output_file = expand_path(cfg.metrics.output_file)
  cfg.tree.outdir = expand_path(cfg.tree.outdir)
  cfg.imports.output_file = expand_path(cfg.imports.output_file)
  if cfg.compress.outdir ~= "" then
    cfg.compress.outdir = expand_path(cfg.compress.outdir)
  end
end

---@param opts InsightsConfig|nil
function M.setup(opts)
  current = vim.tbl_deep_extend("force", defaults, opts or {})
  expand_paths(current)
end

---@return InsightsConfig
function M.get()
  return current
end

return M
