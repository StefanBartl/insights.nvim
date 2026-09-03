---@module 'insights.imports.index'
---@brief The last full import scan, kept so a lookup does not have to repeat it.
---@description
--- **The problem this exists for.** `scan_cwd` walks the working directory,
--- reads every source file it finds and parses each one. Measured on
--- 2026-09-03: 631 ms for hover.nvim, 715 ms for this repository, 1.9 s for
--- documentation.nvim. That is fine for `:Insights imports reverse`, which is
--- a report someone asked for and waits on. It rules out every *passive*
--- consumer -- a statusline, a hover, anything that answers while the reader
--- is reading -- because there was nothing to consult: each query re-scanned.
---
--- So a scan now leaves its result behind. Nothing scans *for* the index; it
--- is a by-product of the scans that already happen, which is why turning it
--- on costs nothing and why a cold index is a normal state rather than a
--- failure.
---
--- **A cold index is answered with `nil`, not with a scan.** A consumer that
--- would trigger a 700 ms walk from a cursor movement is exactly what this
--- was built to avoid, so `get` never builds. Deciding what to do about cold
--- belongs to the caller: a report re-scans, a passive reader declines.
---
--- **Staleness is reported, not guessed at.** A write marks every entry
--- stale, and `get` hands that flag back with the answer rather than throwing
--- it away: an import list from before the last save is usually still the
--- right answer, and pretending it is current is the one thing that would be
--- worse than saying nothing. The same stance `documentation.nvim`'s map
--- preview takes for the same reason.

local M = {}

---@class Insights.ImportIndex.Entry
---@field data ImportData
---@field built_at integer # `os.time()` when the scan finished
---@field stale boolean # a buffer was written since

---@type table<string, Insights.ImportIndex.Entry>
local _by_cwd = {}

---@type boolean Guard for the invalidation autocmd; module-local, not global.
local _hooked = false

---@internal
--- Normalise a directory to the shape `vim.fn.getcwd()` hands back, so a
--- caller passing a path with backslashes or a trailing slash finds the entry
--- a scan left.
---@param dir string|nil
---@return string
local function key(dir)
  local d = tostring(dir or vim.fn.getcwd())
  return (d:gsub("\\", "/"):gsub("/+$", ""))
end

---@internal
--- Mark every entry stale on the next write.
---
--- Every entry rather than the written file's own project: a session has one
--- working directory in practice, and deciding which tree a path belongs to
--- would be a second copy of the walk this module exists to avoid. Marking
--- too much is cheap here -- the flag is reported, not acted on.
---
--- Created the first time something is stored rather than at load: a session
--- that never scans should not carry an autocmd for an index it does not have.
---@return nil
local function hook_invalidation()
  if _hooked then
    return
  end
  _hooked = true
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("InsightsImportIndex", { clear = true }),
    desc = "insights: mark the import index stale",
    callback = function()
      for _, entry in pairs(_by_cwd) do
        entry.stale = true
      end
    end,
  })
end

--- Remember the result of a full scan.
---@param cwd string|nil defaults to the current working directory
---@param data ImportData
---@return nil
function M.put(cwd, data)
  if type(data) ~= "table" then
    return
  end
  hook_invalidation()
  _by_cwd[key(cwd)] = { data = data, built_at = os.time(), stale = false }
end

--- The remembered scan for `cwd`, or nil when there has not been one.
---
--- **Never builds.** A caller that needs an answer either accepts nil or
--- scans on its own account, and the difference between those two is the
--- whole reason this module exists.
---@param cwd string|nil defaults to the current working directory
---@return Insights.ImportIndex.Entry|nil
function M.get(cwd)
  return _by_cwd[key(cwd)]
end

--- Forget everything. Tests, and anything that changes what a scan would find
--- in a way a write does not describe.
---@return nil
function M.forget()
  _by_cwd = {}
end

return M
