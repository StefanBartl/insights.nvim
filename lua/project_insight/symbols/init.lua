---@module 'project_insight.symbols'
---@brief Unified symbol scanner: rg-based (fast, multi-lang) or TS-based (Lua, precise).
---
--- This module merges the function_index (ripgrep) and gather (Tree-sitter) sources.
--- Strategy:
---   • Default: rg_index for all languages, cached.
---   • When `use_treesitter_for_lua = true` in config: TS scanner for Lua,
---     rg_index for all other languages.
local M = {}

local notify   = require("project_insight.util.notify").create("[project_insight.symbols]")
local rg_index = require("project_insight.symbols.rg_index")
local config   = require("project_insight.config")

---Get all symbols for cwd (or current buffer if scope == "buffer").
---@param scope "cwd"|"buffer"|nil    defaults to config.symbols.default_scope
---@param force_rebuild boolean|nil
---@return table[], string|nil   entries, status_message
function M.get(scope, force_rebuild)
  local cfg = config.get()
  scope = scope or cfg.symbols.default_scope or "cwd"

  if scope == "buffer" then
    return M.get_buffer()
  end

  -- CWD scope
  if cfg.symbols.use_treesitter_for_lua then
    return M.get_cwd_ts_lua(cfg, force_rebuild)
  end

  return rg_index.get(cfg, force_rebuild)
end

---Get symbols for the current buffer only.
---@return table[], string|nil
function M.get_buffer()
  local cfg  = config.get()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return {}, "current buffer has no file"
  end

  local sym_cfg = cfg.symbols
  if sym_cfg.use_treesitter_for_lua and vim.bo.filetype == "lua" then
    local ts_lua = require("project_insight.symbols.ts_lua")
    local bufnr  = vim.api.nvim_get_current_buf()
    local matches = ts_lua.scan_buffer(bufnr)
    for _, m in ipairs(matches) do m.filename = path end
    return matches, string.format("%d symbols (TS)", #matches)
  end

  -- rg on the single file
  local rg   = require("project_insight.scan.rg")
  local pat  = require("project_insight.symbols.patterns")
  local pars = require("project_insight.symbols.parser")

  local pats     = pat.get_patterns(sym_cfg.languages)
  local idx_cfg  = sym_cfg.indexing or {}
  local all_lines = {}
  local seen = {}

  for _, p in ipairs(pats) do
    local key = p.language .. "::" .. p.pattern
    if not seen[key] then
      seen[key] = true
      local exts = pat.get_extensions({ [p.language] = true })
      local cmd  = rg.build_cmd(p.pattern, exts, {
        exclude_patterns = idx_cfg.exclude_patterns,
        max_file_size_kb = idx_cfg.max_file_size_kb,
        follow_symlinks  = idx_cfg.follow_symlinks,
        cwd              = path,
      })
      local lines = rg.run(cmd, p.language)
      for _, l in ipairs(lines) do all_lines[#all_lines + 1] = l end
    end
  end

  local entries, errors = pars.parse(all_lines, sym_cfg.languages)
  if #errors > 0 then
    notify.debug(string.format("%d parse errors (buffer scan)", #errors))
  end
  return entries, string.format("%d symbols (buffer)", #entries)
end

---CWD scan with TS for Lua + rg for everything else.
---@param cfg           ProjectInsightConfig
---@param force_rebuild boolean|nil
---@return table[], string|nil
function M.get_cwd_ts_lua(cfg, force_rebuild)
  -- Split language config: Lua via TS, rest via rg
  local non_lua_cfg = vim.deepcopy(cfg)
  non_lua_cfg.symbols.languages.lua = false

  local rg_entries, rg_msg = rg_index.get(non_lua_cfg, force_rebuild)

  local ts_lua   = require("project_insight.symbols.ts_lua")
  local ts_entries = ts_lua.scan_cwd()

  -- Merge: TS entries first (more precise Lua names), then rg entries
  local combined = {}
  for _, e in ipairs(ts_entries) do
    combined[#combined + 1] = vim.tbl_extend("force", e, {
      language  = "lua",
      func_type = "unknown",
      signature = e.name .. "()",
      text      = "",
      col       = e.col or 0,
    })
  end
  for _, e in ipairs(rg_entries) do
    combined[#combined + 1] = e
  end

  local msg = string.format(
    "%d symbols (TS Lua: %d, rg other: %d)",
    #combined, #ts_entries, #rg_entries)
  return combined, msg
end

---Rebuild the rg cache.
---@return table[], string|nil
function M.rebuild()
  return rg_index.rebuild(config.get())
end

return M
