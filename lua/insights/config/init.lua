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

---@internal
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

---@param opts InsightsOpts|nil
function M.setup(opts)
  -- `vim.tbl_deep_extend` only recurses into keys present on *both* sides;
  -- a sub-table `opts` never touches (e.g. `metrics` when only `symbols` was
  -- passed) is carried into the result by reference, not by value. Merging
  -- against a deep copy of `defaults` instead of `defaults` itself means
  -- `expand_paths` below -- which mutates fields of exactly those untouched
  -- sub-tables in place -- can never leak into the shared DEFAULTS module,
  -- even though the effect is currently masked by expand_path being a no-op
  -- on the stdpath()-based absolute defaults.
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  expand_paths(current)
end

---@return InsightsConfig
function M.get()
  return current
end

return M
