---@module 'insights.symbols'
---@brief Unified symbol scanner: rg-based (fast, multi-lang) or TS-based (Lua, precise).
---
--- This module merges the function_index (ripgrep) and gather (Tree-sitter) sources.
--- Strategy:
---   • Default: rg_index for all languages, cached.
---   • When `use_treesitter_for_lua = true` in config: TS scanner for Lua,
---     rg_index for all other languages.
local M = {}

local notify = require("insights.util.notify").create("[insights.symbols]")
local rg_index = require("insights.symbols.rg_index")
local config = require("insights.config")

---Get all symbols for cwd (or current buffer if scope == "buffer").
---@param scope "cwd"|"buffer"|nil    defaults to config.symbols.default_scope
---@param force_rebuild boolean|nil
---@return Insights.Symbols.Match[] entries
---@return string|nil status_message A line for the picker's footer, or nil.
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
  local cfg = config.get()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return {}, "current buffer has no file"
  end

  local sym_cfg = cfg.symbols
  if sym_cfg.use_treesitter_for_lua and vim.bo.filetype == "lua" then
    local ts_lua = require("insights.symbols.ts_lua")
    local bufnr = vim.api.nvim_get_current_buf()
    local matches = ts_lua.scan_buffer(bufnr)
    for _, m in ipairs(matches) do
      m.filename = path
    end
    return matches, string.format("%d symbols (TS)", #matches)
  end

  -- rg on the single file
  local rg = require("insights.scan.rg")
  local pat = require("insights.symbols.patterns")
  local pars = require("insights.symbols.parser")

  local pats = pat.get_patterns(sym_cfg.languages)
  local idx_cfg = sym_cfg.indexing or {}
  local all_lines = {}
  local seen = {}
  local run_errors = {}

  for _, p in ipairs(pats) do
    local key = p.language .. "::" .. p.pattern
    if not seen[key] then
      seen[key] = true
      local exts = pat.get_extensions({ [p.language] = true })
      local cmd = rg.build_cmd(p.pattern, exts, {
        exclude_patterns = idx_cfg.exclude_patterns,
        max_file_size_kb = idx_cfg.max_file_size_kb,
        follow_symlinks = idx_cfg.follow_symlinks,
        cwd = path,
      })
      local lines, run_err = rg.run(cmd, p.language)
      if run_err then
        run_errors[#run_errors + 1] = run_err
      end
      for _, l in ipairs(lines) do
        all_lines[#all_lines + 1] = l
      end
    end
  end

  if #run_errors > 0 then
    notify.warn(string.format("%d rg error(s) during buffer scan: %s", #run_errors, run_errors[1]))
  end

  local entries, errors = pars.parse(all_lines, sym_cfg.languages)
  if #errors > 0 then
    notify.debug(string.format("%d parse errors (buffer scan)", #errors))
  end
  return entries, string.format("%d symbols (buffer)", #entries)
end

---CWD scan with TS for Lua + rg for everything else.
---@param cfg           InsightsConfig
---@param force_rebuild boolean|nil
---@return table[], string|nil
function M.get_cwd_ts_lua(cfg, force_rebuild)
  -- Split language config: Lua via TS, rest via rg
  local non_lua_cfg = vim.deepcopy(cfg)
  non_lua_cfg.symbols.languages.lua = false

  local rg_entries, _ = rg_index.get(non_lua_cfg, force_rebuild)

  local ts_lua = require("insights.symbols.ts_lua")
  local ts_entries = ts_lua.scan_cwd()

  -- Merge: TS entries first (more precise Lua names), then rg entries
  local combined = {}
  for _, e in ipairs(ts_entries) do
    combined[#combined + 1] = vim.tbl_extend("force", e, {
      language = "lua",
      func_type = "unknown",
      signature = e.name .. "()",
      text = "",
      col = e.col or 0,
    })
  end
  for _, e in ipairs(rg_entries) do
    combined[#combined + 1] = e
  end

  local msg =
    string.format("%d symbols (TS Lua: %d, rg other: %d)", #combined, #ts_entries, #rg_entries)
  return combined, msg
end

---Rebuild the rg cache.
---@return table[], string|nil
function M.rebuild()
  return rg_index.rebuild(config.get())
end

---Get Lua table definitions for the given scope.
---@param scope "cwd"|"buffer"|nil
---@return table[], string|nil
function M.get_tables(scope)
  scope = scope or "buffer"
  local scanner = require("insights.symbols.ts_lua_tables")

  if scope == "buffer" then
    local path = vim.api.nvim_buf_get_name(0)
    local bufnr = vim.api.nvim_get_current_buf()
    local result = scanner.scan_buffer(bufnr)
    for _, e in ipairs(result) do
      e.filename = path
    end
    return result, string.format("%d tables (buffer)", #result)
  end

  local entries = scanner.scan_cwd()
  return entries, string.format("%d tables (cwd)", #entries)
end

---Get Lua string literals for the given scope.
---@param scope "cwd"|"buffer"|nil
---@return table[], string|nil
function M.get_strings(scope)
  scope = scope or "buffer"
  local scanner = require("insights.symbols.ts_lua_strings")

  if scope == "buffer" then
    local path = vim.api.nvim_buf_get_name(0)
    local bufnr = vim.api.nvim_get_current_buf()
    local result = scanner.scan_buffer(bufnr)
    for _, e in ipairs(result) do
      e.filename = path
    end
    return result, string.format("%d strings (buffer)", #result)
  end

  local entries = scanner.scan_cwd()
  return entries, string.format("%d strings (cwd)", #entries)
end

return M
