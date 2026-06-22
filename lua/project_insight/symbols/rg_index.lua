---@module 'project_insight.symbols.rg_index'
---@brief Ripgrep-based symbol indexer with cache support.
local M = {}

local notify   = require("project_insight.util.notify").create("[project_insight.symbols.rg_index]")
local rg       = require("project_insight.scan.rg")
local cache    = require("project_insight.scan.cache")
local patterns = require("project_insight.symbols.patterns")
local parser   = require("project_insight.symbols.parser")

---Build a fresh index; returns (entries, errors, stats).
---@param cfg ProjectInsightConfig
---@return table[], string[], { total_files: integer, total_symbols: integer, duration: number }
function M.build(cfg)
  local sym_cfg = cfg.symbols
  local t0 = os.time()

  if vim.fn.executable("rg") ~= 1 then
    local msg = "ripgrep (rg) not found in PATH"
    return {}, { msg }, { total_files=0, total_symbols=0, duration=0 }
  end

  local pats = patterns.get_patterns(sym_cfg.languages)
  if #pats == 0 then
    return {}, { "no languages enabled" }, { total_files=0, total_symbols=0, duration=0 }
  end

  local idx_cfg = sym_cfg.indexing or {}
  local all_lines, errors = {}, {}
  local seen_patterns = {}

  for _, pat in ipairs(pats) do
    local key = pat.language .. "::" .. pat.pattern
    if not seen_patterns[key] then
      seen_patterns[key] = true
      local exts = patterns.get_extensions({ [pat.language] = true })
      local cmd = rg.build_cmd(pat.pattern, exts, {
        exclude_patterns = idx_cfg.exclude_patterns,
        max_file_size_kb = idx_cfg.max_file_size_kb,
        follow_symlinks  = idx_cfg.follow_symlinks,
      })
      local lines = rg.run(cmd, pat.language)
      for _, l in ipairs(lines) do
        all_lines[#all_lines + 1] = l
      end
    end
  end

  notify.debug(string.format("rg produced %d lines", #all_lines))

  local entries, parse_errors = parser.parse(all_lines, sym_cfg.languages)
  for _, e in ipairs(parse_errors) do errors[#errors + 1] = e end

  local files = {}
  for _, e in ipairs(entries) do files[e.filename] = true end
  local file_count = 0
  for _ in pairs(files) do file_count = file_count + 1 end

  return entries, errors, {
    total_files   = file_count,
    total_symbols = #entries,
    duration      = os.time() - t0,
  }
end

---Get index (from cache or fresh build).
---@param cfg           ProjectInsightConfig
---@param force_rebuild boolean|nil
---@return table[], string|nil   entries, status_message
function M.get(cfg, force_rebuild)
  local c = cfg.symbols.cache

  if not force_rebuild and c.enabled then
    local cached, reason = cache.load(c.dir, "symbols", c.ttl_seconds)
    if cached then
      return cached, string.format("cache: %d symbols", #cached)
    end
    if reason then notify.debug("cache miss: " .. reason) end
  end

  local entries, errors, stats = M.build(cfg)
  if #errors > 0 then
    notify.warn(string.format(
      "built index with %d errors (%d symbols in %d files)",
      #errors, stats.total_symbols, stats.total_files))
  end

  if c.enabled and #entries > 0 then
    local ok, err = cache.save(c.dir, "symbols", entries)
    if not ok then notify.warn("cache save failed: " .. tostring(err)) end
  end

  return entries, string.format(
    "indexed %d symbols in %d files (%ds)",
    stats.total_symbols, stats.total_files, stats.duration)
end

---Rebuild cache.
---@param cfg ProjectInsightConfig
---@return table[], string|nil
function M.rebuild(cfg)
  local c = cfg.symbols.cache
  if c.enabled then
    cache.clear(c.dir, "symbols")
  end
  return M.get(cfg, true)
end

return M
