---@module 'insights.scan.cache'
---@brief Generic JSON cache keyed by CWD sha256.
local M = {}

local uv = vim.uv or vim.loop

local CACHE_VERSION = "1.0.0"

---@internal
---`variant` folds in every parameter besides the CWD that changes what a
---rebuild would produce (e.g. which languages/patterns were scanned) --
---without it, two different configurations of the same directory silently
---share one cache entry and answer each other's question (PERF-46).
---@param dir string
---@param ns  string  namespace slug (e.g. "symbols")
---@param variant string|nil
---@return string
local function cache_path(dir, ns, variant)
  local cwd = vim.fn.getcwd()
  local hash = vim.fn.sha256(cwd .. "\30" .. (variant or "")):sub(1, 16)
  return dir .. "/" .. ns .. "_" .. hash .. ".json"
end

---@internal
---@param path string
---@return integer|nil
local function get_mtime(path)
  local st = uv.fs_stat(path)
  return st and st.mtime.sec or nil
end

---Load cached entries if valid; returns (entries|nil, reason_string|nil).
---@param dir string   cache directory
---@param ns  string   namespace slug
---@param ttl_seconds integer
---@param variant string|nil  see `cache_path`
---@return table[]|nil, string|nil
function M.load(dir, ns, ttl_seconds, variant)
  local path = cache_path(dir, ns, variant)
  local decoded, read_err = require("lib.nvim.fs.json").read(path)
  if not decoded then
    return nil, read_err or "no cache file"
  end

  if decoded.version ~= CACHE_VERSION then
    return nil, "version mismatch"
  end
  if decoded.cwd ~= vim.fn.getcwd() then
    return nil, "different CWD"
  end
  if ttl_seconds and ttl_seconds > 0 then
    local age = os.time() - (decoded.indexed_at or 0)
    if age > ttl_seconds then
      return nil, string.format("expired (%ds old, TTL %ds)", age, ttl_seconds)
    end
  end

  -- Check file mtimes for invalidation
  local entries = decoded.entries or {}
  for _, ie in ipairs(entries) do
    local cur = get_mtime(ie.entry and ie.entry.filename or "")
    if not cur or (ie.file_mtime and cur > ie.file_mtime) then
      return nil, "source files changed"
    end
  end

  local result = {}
  for _, ie in ipairs(entries) do
    result[#result + 1] = ie.entry
  end
  return result, nil
end

---Save entries to cache.
---@param dir string
---@param ns  string
---@param entries table[]  must each have a `.filename` field
---@param variant string|nil  see `cache_path`
---@return boolean, string|nil
function M.save(dir, ns, entries, variant)
  local index_entries = {}
  for _, e in ipairs(entries) do
    index_entries[#index_entries + 1] = {
      entry = e,
      file_mtime = get_mtime(e.filename) or os.time(),
      indexed_at = os.time(),
    }
  end

  local blob = {
    version = CACHE_VERSION,
    indexed_at = os.time(),
    cwd = vim.fn.getcwd(),
    entries = index_entries,
  }

  local path = cache_path(dir, ns, variant)
  return require("lib.nvim.fs.json").write(path, blob)
end

---Delete cache file for current CWD.
---@param dir string
---@param ns  string
---@param variant string|nil  see `cache_path`
---@return boolean, string|nil
function M.clear(dir, ns, variant)
  local path = cache_path(dir, ns, variant)
  local ok, err = pcall(uv.fs_unlink, path)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

---Return cache stats or nil if no cache exists.
---@param dir string
---@param ns  string
---@param variant string|nil  see `cache_path`
---@return table|nil
function M.stats(dir, ns, variant)
  local path = cache_path(dir, ns, variant)
  local decoded = require("lib.nvim.fs.json").read(path)
  if not decoded then
    return nil
  end
  local file_stat = uv.fs_stat(path)
  return {
    version = decoded.version,
    indexed_at = decoded.indexed_at,
    cwd = decoded.cwd,
    entry_count = #(decoded.entries or {}),
    size_bytes = file_stat and file_stat.size or 0,
    path = path,
  }
end

return M
