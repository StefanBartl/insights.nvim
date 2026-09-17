-- TESTS/scan_cache_spec.lua — the on-disk symbol cache.
--
-- Everything here is real file I/O into a fixture directory: the cache is a
-- JSON file, and the questions worth asking of it are about invalidation --
-- version, working directory, age, and whether the indexed files have been
-- touched since. A stubbed filesystem would answer none of them.

return function(H)
  local cache = require("insights.scan.cache")

  local dir, cleanup = H.fixture("scan-cache")
  local cache_dir = dir .. "/cachedir"
  local src = dir .. "/src.lua"
  vim.fn.writefile({ "local function f() end" }, src)

  ---@param filename string
  ---@param name string
  ---@return table
  local function entry(filename, name)
    return { filename = filename, name = name, lnum = 1, col = 1, language = "lua" }
  end

  -- Cold --------------------------------------------------------------------
  local cold, cold_reason = cache.load(cache_dir, "symbols", 0)
  H.eq(cold, nil, "a cache that was never written loads nothing")
  H.ok(type(cold_reason) == "string", "with a reason")
  H.eq(cache.stats(cache_dir, "symbols"), nil, "and has no stats")

  -- Save and load back ------------------------------------------------------
  local ok_save, save_err = cache.save(cache_dir, "symbols", { entry(src, "f") })
  H.ok(ok_save, "saving creates the cache file")
  H.eq(save_err, nil, "with no error")

  local warm, warm_reason = cache.load(cache_dir, "symbols", 0)
  H.ok(warm, "and it loads back")
  H.eq(warm_reason, nil, "with no miss reason")
  H.eq(#warm, 1, "holding the entries it was given")
  H.eq(warm[1].name, "f", "unwrapped from the index record they were stored in")
  H.eq(warm[1].filename, src, "with their own fields intact")

  -- stats --------------------------------------------------------------------
  local stats = cache.stats(cache_dir, "symbols")
  H.ok(stats, "stats answers once there is a cache")
  H.eq(stats.entry_count, 1, "counting the stored entries")
  H.eq(stats.cwd, vim.fn.getcwd(), "recording the directory it was built for")
  H.ok(type(stats.indexed_at) == "number", "and when")
  H.ok(stats.size_bytes > 0, "with the file's size")
  H.contains(stats.path, "symbols_", "and its path, namespaced")

  -- The path is keyed by the *current* working directory, so two projects
  -- never share a cache file.
  H.contains(stats.path, cache_dir, "inside the configured cache directory")
  H.contains(stats.path, ".json", "as JSON")

  -- TTL ----------------------------------------------------------------------
  H.ok(cache.load(cache_dir, "symbols", 3600), "a fresh cache is inside a one-hour TTL")
  -- A TTL of zero (or less) disables the age check entirely rather than
  -- expiring everything immediately.
  H.ok(cache.load(cache_dir, "symbols", 0), "a TTL of 0 means no age check")

  -- Rewrite the stored `indexed_at` into the past and the age check bites.
  local json = require("lib.nvim.fs.json")
  local blob = json.read(stats.path)
  blob.indexed_at = os.time() - 10000
  json.write(stats.path, blob)
  local expired, expired_reason = cache.load(cache_dir, "symbols", 60)
  H.eq(expired, nil, "a cache older than the TTL is a miss")
  H.contains(expired_reason or "", "expired", "and says so")

  -- Version ------------------------------------------------------------------
  blob = json.read(stats.path)
  blob.indexed_at = os.time()
  blob.version = "0.0.1-from-an-older-insights"
  json.write(stats.path, blob)
  local stale_version, version_reason = cache.load(cache_dir, "symbols", 0)
  H.eq(stale_version, nil, "a cache written by another version is a miss")
  H.eq(version_reason, "version mismatch", "named exactly")

  -- Working directory --------------------------------------------------------
  blob = json.read(stats.path)
  blob.version = "1.0.0"
  blob.cwd = "/somewhere/else/entirely"
  json.write(stats.path, blob)
  local other_cwd, cwd_reason = cache.load(cache_dir, "symbols", 0)
  H.eq(other_cwd, nil, "a cache built for another directory is a miss")
  H.eq(cwd_reason, "different CWD", "named exactly")

  -- Source mtime -------------------------------------------------------------
  -- The point of the whole file: an index whose sources changed is wrong, and
  -- silently serving it is worse than rebuilding.
  cache.save(cache_dir, "symbols", { entry(src, "f") })
  H.ok(cache.load(cache_dir, "symbols", 0), "a cache matching its sources loads")

  blob = json.read(stats.path)
  blob.entries[1].file_mtime = 1
  json.write(stats.path, blob)
  local touched, touched_reason = cache.load(cache_dir, "symbols", 0)
  H.eq(touched, nil, "a source newer than the record is a miss")
  H.eq(touched_reason, "source files changed", "named exactly")

  -- A recorded file that no longer exists is the same kind of miss: the
  -- index describes a tree that is gone.
  cache.save(cache_dir, "symbols", { entry(dir .. "/deleted.lua", "gone") })
  local vanished, vanished_reason = cache.load(cache_dir, "symbols", 0)
  H.eq(vanished, nil, "a recorded file that is not there is a miss")
  H.eq(vanished_reason, "source files changed", "under the same reason")

  -- Namespaces are separate --------------------------------------------------
  cache.save(cache_dir, "symbols", { entry(src, "f") })
  cache.save(cache_dir, "other", { entry(src, "g"), entry(src, "h") })
  H.eq(#cache.load(cache_dir, "symbols", 0), 1, "one namespace keeps its own entries")
  H.eq(#cache.load(cache_dir, "other", 0), 2, "and the other keeps its own")
  H.ok(
    cache.stats(cache_dir, "symbols").path ~= cache.stats(cache_dir, "other").path,
    "in separate files"
  )

  -- clear --------------------------------------------------------------------
  local ok_clear, clear_err = cache.clear(cache_dir, "symbols")
  H.ok(ok_clear, "clearing removes the file")
  H.eq(clear_err, nil, "without an error")
  H.eq(cache.load(cache_dir, "symbols", 0), nil, "and the cache is cold again")
  H.ok(cache.load(cache_dir, "other", 0), "while the other namespace survives")

  -- Clearing again is a no-op, not a failure. `uv.fs_unlink` reports a missing
  -- file by returning `nil, err` rather than raising, and `clear` only guards
  -- against a raise -- so `:Insights cache clear` says "cache cleared" whether
  -- or not there was one. Pinned as the behaviour, not fixed: idempotent is
  -- the useful answer for a clear, and the alternative would be an error
  -- message for doing nothing wrong.
  local ok_again, again_err = cache.clear(cache_dir, "symbols")
  H.ok(ok_again, "clearing an already-cleared cache still answers ok")
  H.eq(again_err, nil, "with no error")

  -- A record whose entry names no file cannot be verified against the tree.
  -- `save` requires a `.filename` per its own contract, so this can only come
  -- from a hand-edited or older cache file -- and it is treated as a miss
  -- rather than trusted.
  cache.save(cache_dir, "nameless", { entry(src, "f") })
  local nameless_path = cache.stats(cache_dir, "nameless").path
  local nameless_blob = json.read(nameless_path)
  nameless_blob.entries[1].entry.filename = nil
  json.write(nameless_path, nameless_blob)
  local nameless, nameless_reason = cache.load(cache_dir, "nameless", 0)
  H.eq(nameless, nil, "an entry naming no file cannot be verified")
  H.eq(nameless_reason, "source files changed", "so the whole cache is rebuilt")

  cleanup()
end
