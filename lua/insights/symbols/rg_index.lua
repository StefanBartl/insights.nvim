---@module 'insights.symbols.rg_index'
---@brief Ripgrep-based symbol indexer with cache support.
local M = {}

local notify   = require("insights.util.notify").create("[insights.symbols.rg_index]")
local rg       = require("insights.scan.rg")
local cache    = require("insights.scan.cache")
local patterns = require("insights.symbols.patterns")
local parser   = require("insights.symbols.parser")

local ok_progress, progress_mod = pcall(require, "lib.nvim.progress")

---@internal
---Starts an indicator for an index build, or nil when lib.nvim isn't installed.
---
---This works despite `M.build` being synchronous because `rg.exec_sync` waits
---via `vim.wait`, which pumps the event loop — so the delay-guard timer fires
---and the statusline repaints between passes. It would be dead code against a
---`vim.fn.systemlist`-style block; see the note in `insights.scan.rg`.
---@param total integer Number of distinct rg passes about to run
---@param style string|nil
---@return table|nil
local function start_progress(total, style)
  if not ok_progress then
    return nil
  end
  local handle = progress_mod.create({ title = "[insights]", style = style or "auto" })
  handle:update({ text = string.format("indexing symbols (%d passes)", total), current = 0, total = total })
  return handle
end

---Build a fresh index; returns (entries, errors, stats).
---@param cfg InsightsConfig
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

  -- Count the distinct passes up front rather than using `#pats`: duplicate
  -- language/pattern pairs are skipped below, so `#pats` would promise more work
  -- than actually happens and the indicator would stall short of its total.
  local total_passes = 0
  do
    local counted = {}
    for _, pat in ipairs(pats) do
      local key = pat.language .. "::" .. pat.pattern
      if not counted[key] then
        counted[key] = true
        total_passes = total_passes + 1
      end
    end
  end

  local progress = start_progress(total_passes, sym_cfg.progress_style)
  local pass = 0

  for _, pat in ipairs(pats) do
    local key = pat.language .. "::" .. pat.pattern
    if not seen_patterns[key] then
      seen_patterns[key] = true

      -- Named before the pass runs: each rg call scans the whole tree, so this
      -- is what the user is waiting on, not what just finished.
      if progress then
        progress:update({
          text = string.format("%s (%d symbols so far)", pat.language, #all_lines),
          current = pass,
          total = total_passes,
        })
      end

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
      pass = pass + 1
    end
  end

  if progress then
    progress:finish(string.format("indexed %d matches", #all_lines))
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
---@param cfg           InsightsConfig
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
---@param cfg InsightsConfig
---@return table[], string|nil
function M.rebuild(cfg)
  local c = cfg.symbols.cache
  if c.enabled then
    cache.clear(c.dir, "symbols")
  end
  return M.get(cfg, true)
end

return M
