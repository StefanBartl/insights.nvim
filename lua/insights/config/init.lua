---@module 'insights.config'
--- Merges user options (from setup()) over the plugin's defaults.
--- See config/DEFAULTS.lua for the default values and config/@types for
--- their types.

require("insights.config.@types")

local expand_path = require("lib.nvim.cross.fs.expand_path")
local islist = vim.islist or vim.tbl_islist

local M = {}

---@type InsightsConfig
local defaults = require("insights.config.DEFAULTS")

---@type InsightsConfig
local current = vim.deepcopy(defaults)

-- Sub-tables with arbitrary user-chosen keys, not a fixed known set -- a new
-- entry here is not a typo and must never be reported as an unknown key.
local OPEN_KEY_PATHS = {
  ["imports.groups"] = true,
  ["todos.keywords"] = true,
  ["todos.colors"] = true,
}

---Config issues found by the last setup() call: an unknown key (with a "did
---you mean" hint when a close one exists) or a value -- at any nesting --
---whose type didn't match its default. Surfaced by :checkhealth
---(ERR-22/ERR-50).
---@type string[]
local last_issues = {}

---@internal
---@param path string
---@return boolean
local function is_leaf_table(default_v, path)
  return type(default_v) ~= "table" or islist(default_v) or OPEN_KEY_PATHS[path]
end

---@internal
---The known key of `default_tbl` nearest to the unrecognized `name`, the
---same distance-bounded nearest-match lookup `lib.config` itself uses for
---its own "did you mean" hint.
---@param name string
---@param default_tbl table
---@return string|nil
local function nearest_sibling(name, default_tbl)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local best, best_distance = nil, nil
  for known in pairs(default_tbl) do
    if type(known) == "string" then
      local d = levenshtein(name, known)
      if d <= 3 and (best_distance == nil or d < best_distance) then
        best, best_distance = known, d
      end
    end
  end
  return best
end

---@internal
---Recursively warn about keys in `user_tbl` that do not exist in
---`default_tbl` at the same nesting, so a typo in a nested option cannot
---vanish silently into the default (ERR-50). Run *before* the merge.
---@param user_tbl table
---@param default_tbl table
---@param path string
---@param issues string[]
local function check_known_keys(user_tbl, default_tbl, path, issues)
  for k, v in pairs(user_tbl) do
    local full = path == "" and tostring(k) or (path .. "." .. tostring(k))
    if type(k) ~= "string" or default_tbl[k] == nil then
      local suggestion = type(k) == "string" and nearest_sibling(k, default_tbl) or nil
      issues[#issues + 1] = suggestion and ("%s (did you mean `%s`?)"):format(full, suggestion)
        or full
    elseif
      type(v) == "table"
      and type(default_tbl[k]) == "table"
      and not is_leaf_table(default_tbl[k], full)
    then
      check_known_keys(v, default_tbl[k], full, issues)
    end
  end
end

---@internal
---A key whose default is a *sub-table* but whose user-supplied value is not
---(e.g. `compress = false`, or the same one level down as `symbols = {
---cache = false }`) must degrade to the default instead of letting the merge
---replace that sub-table with a scalar -- every later consumer that indexes
---into it would otherwise crash on plugin init (ERR-22). Walks the full
---nested shape, not just the top level: a mistyped sub-table is exactly as
---fatal to e.g. `expand_paths` three levels down as it is at the top.
---
---Deliberately *not* a general type check, and deliberately scoped to the
---same "leaf" notion `check_known_keys` already uses (`is_leaf_table`):
---
---  * A scalar leaf (e.g. `ui.follow_key`, `keymaps.symbols_fzf`) is never
---    checked here at all. Several of these are documented to accept
---    `false` as "disable this" even though their default is a string --
---    that is a valid union, not a mistake, and consuming code already
---    guards for it (`if x and x ~= false then ... end`).
---  * A list-shaped or open-key default (`conflicts.events`,
---    `imports.groups`, ...) is also never checked here. `events` in
---    particular is documented and tested to accept a single string as
---    shorthand for a one-element list (`norm_events` in
---    `bindings/autocmds.lua` normalizes it); an open-key table has no
---    fixed shape to check against in the first place.
---  * Only a *record* sub-table -- fixed named keys, not a list, not an
---    open-key path -- is checked, because that is the only shape whose
---    replacement by a non-table crashes a later consumer that indexes into
---    it by name (`cfg.symbols.cache.dir`, ERR-22).
---
---Returns a shallow-cloned copy of `user_tbl` with any such key (at any
---depth) removed; `user_tbl` itself is left untouched.
---@param user_tbl table
---@param default_tbl table
---@param path string
---@param issues string[]
---@return table
local function drop_mistyped(user_tbl, default_tbl, path, issues)
  local cleaned = {}
  for k, v in pairs(user_tbl) do
    cleaned[k] = v
  end
  for k, default_v in pairs(default_tbl) do
    local full = path == "" and tostring(k) or (path .. "." .. tostring(k))
    if type(default_v) == "table" and not is_leaf_table(default_v, full) then
      local v = cleaned[k]
      if v ~= nil then
        if type(v) ~= "table" then
          issues[#issues + 1] = ("%s: expected table, got %s -- using the default"):format(
            full,
            type(v)
          )
          cleaned[k] = nil
        else
          cleaned[k] = drop_mistyped(v, default_v, full, issues)
        end
      end
    end
  end
  return cleaned
end

---@internal
---Validate `opts` against the default shape before it is merged in.
---@param opts table
---@return table sanitized  a shallow copy safe to merge
local function sanitize(opts)
  local issues = {}
  check_known_keys(opts, defaults, "", issues)
  local cleaned = drop_mistyped(opts, defaults, "", issues)

  last_issues = issues
  if #issues > 0 then
    vim.notify(
      "[insights] config issue(s) in setup():\n  - " .. table.concat(issues, "\n  - "),
      vim.log.levels.WARN
    )
  end
  return cleaned
end

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
  local sanitized = sanitize(opts or {})

  -- `vim.tbl_deep_extend` only recurses into keys present on *both* sides;
  -- a sub-table `opts` never touches (e.g. `metrics` when only `symbols` was
  -- passed) is carried into the result by reference, not by value. Merging
  -- against a deep copy of `defaults` instead of `defaults` itself means
  -- `expand_paths` below -- which mutates fields of exactly those untouched
  -- sub-tables in place -- can never leak into the shared DEFAULTS module,
  -- even though the effect is currently masked by expand_path being a no-op
  -- on the stdpath()-based absolute defaults.
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), sanitized)
  expand_paths(current)
end

---@return InsightsConfig
function M.get()
  return current
end

---@return string[]
function M.issues()
  return last_issues
end

return M
