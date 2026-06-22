---@module 'project_insight.scan.cache'
---@brief Generic JSON cache keyed by CWD sha256.
local M = {}

local uv = vim.uv or vim.loop

local CACHE_VERSION = "1.0.0"

local function ensure_dir(dir)
  local stat = uv.fs_stat(dir)
  if stat then
    if stat.type ~= "directory" then
      return false, dir .. " exists but is not a directory"
    end
    return true, nil
  end
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if not ok then return false, tostring(err) end
  return true, nil
end

---@param dir string
---@param ns  string  namespace slug (e.g. "symbols")
---@return string
local function cache_path(dir, ns)
  local cwd  = vim.fn.getcwd()
  local hash = vim.fn.sha256(cwd):sub(1, 16)
  return dir .. "/" .. ns .. "_" .. hash .. ".json"
end

local function get_mtime(path)
  local st = uv.fs_stat(path)
  return st and st.mtime.sec or nil
end

---Load cached entries if valid; returns (entries|nil, reason_string|nil).
---@param dir string   cache directory
---@param ns  string   namespace slug
---@param ttl_seconds integer
---@return table[]|nil, string|nil
function M.load(dir, ns, ttl_seconds)
  local path = cache_path(dir, ns)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then return nil, "no cache file" end

  local stat = uv.fs_fstat(fd)
  if not stat then uv.fs_close(fd); return nil, "stat failed" end
  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  if not data then return nil, "read failed" end

  local ok, decoded = pcall(vim.fn.json_decode, data)
  if not ok or type(decoded) ~= "table" then return nil, "decode failed" end

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
---@return boolean, string|nil
function M.save(dir, ns, entries)
  local ok, err = ensure_dir(dir)
  if not ok then return false, err end

  local index_entries = {}
  for _, e in ipairs(entries) do
    index_entries[#index_entries + 1] = {
      entry      = e,
      file_mtime = get_mtime(e.filename) or os.time(),
      indexed_at = os.time(),
    }
  end

  local blob = {
    version    = CACHE_VERSION,
    indexed_at = os.time(),
    cwd        = vim.fn.getcwd(),
    entries    = index_entries,
  }

  local ok2, encoded = pcall(vim.fn.json_encode, blob)
  if not ok2 then return false, "encode failed: " .. tostring(encoded) end

  local path = cache_path(dir, ns)
  local fd = uv.fs_open(path, "w", 420)
  if not fd then return false, "open for write failed" end
  uv.fs_write(fd, encoded, 0)
  uv.fs_close(fd)

  return true, nil
end

---Delete cache file for current CWD.
---@param dir string
---@param ns  string
---@return boolean, string|nil
function M.clear(dir, ns)
  local path = cache_path(dir, ns)
  local ok, err = pcall(uv.fs_unlink, path)
  if not ok then return false, tostring(err) end
  return true, nil
end

---Return cache stats or nil if no cache exists.
---@param dir string
---@param ns  string
---@return table|nil
function M.stats(dir, ns)
  local path = cache_path(dir, ns)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then return nil end
  local stat2 = uv.fs_fstat(fd)
  local data  = stat2 and uv.fs_read(fd, stat2.size, 0) or nil
  uv.fs_close(fd)
  if not data then return nil end
  local ok, decoded = pcall(vim.fn.json_decode, data)
  if not ok then return nil end
  local file_stat = uv.fs_stat(path)
  return {
    version    = decoded.version,
    indexed_at = decoded.indexed_at,
    cwd        = decoded.cwd,
    entry_count = #(decoded.entries or {}),
    size_bytes = file_stat and file_stat.size or 0,
    path       = path,
  }
end

return M
