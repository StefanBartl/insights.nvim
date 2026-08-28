---@module 'insights.smells'
---@brief Two code-smell scans over a project's Lua source, distinct from
---`insights.metrics`'s size/ratio analysis: numbers written straight into a
---call with no name to configure, and named constants that describe
---behaviour but never made it into the project's own config surface.
---@description
---Promoted from two throwaway Python scripts in nvim-config
---(`docs/ROADMAP/tools/magic_numbers.py` / `hardcoded_constants.py`), ported
---to run against one project via `insights.metrics.analyzer.get_lua_files`
---instead of a hardcoded multi-repo root — this module never compares across
---projects (see `lib.nvim.dev.duplicates` for the cross-repo question that
---was; a different question, correctly living somewhere else).
---
---Candidates, not verdicts, for both scans: plenty of constants should stay
---constants, and a short defer/wait exists to get off the current tick, not
---to be a setting.

local M = {}

local analyzer = require("insights.metrics.analyzer")

-- ── magic numbers ─────────────────────────────────────────────────────────

---@class Insights.Smells.MagicNumber
---@field rel string
---@field lnum integer
---@field kind string
---@field value string
---@field src string   the source line, trimmed

---@internal
local MAGIC_PATTERNS = {
  { "defer", "vim%.defer_fn%s*%([^,]*,%s*(%d+)%s*%)" },
  { "wait", "vim%.wait%s*%(%s*(%d+)" },
  { "timer", ":start%s*%(%s*(%d+)%s*,%s*(%d+)" },
  { "timeout", "timeout%s*=%s*(%d+)" },
  { "frac_cols", "vim%.o%.columns%s*%*%s*(0?%.%d+)" },
  { "frac_lines", "vim%.o%.lines%s*%*%s*(0?%.%d+)" },
}

-- A defer/wait/timer this short is "get off the current tick", not a
-- preference — not worth flagging.
local TICK_MAX = 50

---Scan `root`'s Lua files for behaviour numbers written straight into a
---call, with no name to hold a config key against.
---@param root string  normalized (absolute, forward slashes, no trailing slash)
---@return Insights.Smells.MagicNumber[]
function M.magic_numbers(root)
  local out = {}
  for _, path in ipairs(analyzer.get_lua_files(root)) do
    local fd = io.open(path, "r")
    if fd then
      local rel = path:sub(#root + 2)
      local lnum = 0
      for line in fd:lines() do
        lnum = lnum + 1
        local stripped = vim.trim(line)
        if not vim.startswith(stripped, "--") then
          for _, p in ipairs(MAGIC_PATTERNS) do
            local kind, pattern = p[1], p[2]
            local value = line:match(pattern)
            if value then
              local skip = (kind == "defer" or kind == "wait" or kind == "timer")
                and tonumber(value)
                and tonumber(value) <= TICK_MAX
              if not skip then
                out[#out + 1] =
                  { rel = rel, lnum = lnum, kind = kind, value = value, src = stripped:sub(1, 78) }
              end
            end
          end
        end
      end
      fd:close()
    end
  end
  return out
end

-- ── hardcoded (unconfigurable) constants ────────────────────────────────

---@class Insights.Smells.HardcodedConstant
---@field rel string
---@field lnum integer
---@field name string
---@field value string

-- Names describing behaviour a user might reasonably want to change. A
-- plain list, not one alternation pattern -- Lua patterns have no `|`, so
-- each candidate substring is checked in turn (`ms$` becomes its own
-- suffix check below, everything else is a plain substring test).
local BEHAVIOUR_SUBSTRINGS = {
  "timeout",
  "delay",
  "debounce",
  "interval",
  "max",
  "min",
  "limit",
  "cap",
  "width",
  "height",
  "size",
  "count",
  "threshold",
  "retry",
  "attempts",
  "_ms",
  "padding",
  "depth",
  "lines",
  "chars",
  "budget",
}

---@internal
---@param name string
---@return boolean
local function looks_like_behaviour(name)
  local lower = name:lower()
  if lower:sub(-2) == "ms" then
    return true
  end
  for _, s in ipairs(BEHAVIOUR_SUBSTRINGS) do
    if lower:find(s, 1, true) then
      return true
    end
  end
  return false
end

---@internal
---SCREAMING_CASE, or a bare integer value that is not 0/1 (a counter's
---starting point, not a tuned constant).
---@param name string
---@param value string
---@return boolean
local function is_constant(name, value)
  if name == name:upper() then
    return true
  end
  local n = value:match("^%d+$")
  return n ~= nil and n ~= "0" and n ~= "1"
end

---@internal
---Whether `path` looks like part of the project's own config surface —
---the same four-way test the original script used.
---@param path string
---@return boolean
local function is_config_path(path)
  local low = path:lower()
  if low:find("/config/", 1, true) or low:find("/@types/", 1, true) then
    return true
  end
  local name = path:match("([^/]+)$") or ""
  if name:lower():find("defaults") then
    return true
  end
  return (name == "types.lua" or name == "init.lua") and low:find("/config", 1, true) ~= nil
end

---@internal
---Everything that looks like `root`'s config surface, as one lowercase blob.
---@param root string
---@return string
local function config_blob(root)
  local parts = {}
  for _, path in ipairs(analyzer.get_lua_files(root)) do
    if is_config_path(path) then
      local fd = io.open(path, "r")
      if fd then
        parts[#parts + 1] = fd:read("*a")
        fd:close()
      end
    end
  end
  return table.concat(parts, "\n"):lower()
end

---Scan `root`'s Lua files for module-level constants that describe
---behaviour but are reachable from no config key.
---@param root string  normalized (absolute, forward slashes, no trailing slash)
---@return Insights.Smells.HardcodedConstant[]
function M.hardcoded_constants(root)
  local cfg = config_blob(root)
  if cfg == "" then
    return {}
  end

  local out = {}
  for _, path in ipairs(analyzer.get_lua_files(root)) do
    if not is_config_path(path) then
      local fd = io.open(path, "r")
      if fd then
        local rel = path:sub(#root + 2)
        local lnum = 0
        for line in fd:lines() do
          lnum = lnum + 1
          local name, value = line:match("^local%s+([%a_][%w_]*)%s*=%s*(%d+)%s*$")
          if not name then
            name, value = line:match('^local%s+([%a_][%w_]*)%s*=%s*"([^"]*)"%s*$')
          end
          if name and looks_like_behaviour(name) and is_constant(name, value) then
            local key = name:lower():gsub("^_+", "")
            local without_default = key:gsub("^default_", "")
            if not (cfg:find(key, 1, true) or cfg:find(without_default, 1, true)) then
              out[#out + 1] = { rel = rel, lnum = lnum, name = name, value = value:sub(1, 48) }
            end
          end
        end
        fd:close()
      end
    end
  end
  return out
end

-- ── report ────────────────────────────────────────────────────────────────

---@class Insights.Smells.Opts
---@field root string|nil
---@field magic_numbers boolean|nil    # default true
---@field hardcoded_constants boolean|nil  # default true

---Run both scans (or one, per `opts`) and open the report in a scratch
---buffer.
---@param opts Insights.Smells.Opts|nil
function M.run(opts)
  opts = opts or {}
  local notify = require("insights.util.notify").create("[insights.smells]")
  local root = require("insights.metrics").normalize_dir(
    (opts.root and opts.root ~= "" and opts.root) or vim.fn.getcwd()
  )
  if vim.fn.isdirectory(root) == 0 then
    notify.warn("not a directory: " .. root)
    return
  end

  local want_magic = opts.magic_numbers ~= false
  local want_const = opts.hardcoded_constants ~= false

  local lines = { "=== Code Smells ===", "Root: " .. root, "" }

  if want_magic then
    local hits = M.magic_numbers(root)
    lines[#lines + 1] = ("-- Magic numbers: %d"):format(#hits)
    for _, h in ipairs(hits) do
      lines[#lines + 1] = ("   %-46s %-10s %-6s %s"):format(
        h.rel .. ":" .. h.lnum,
        h.kind,
        h.value,
        h.src
      )
    end
    lines[#lines + 1] = ""
  end

  if want_const then
    local hits = M.hardcoded_constants(root)
    lines[#lines + 1] = ("-- Hardcoded constants: %d"):format(#hits)
    for _, h in ipairs(hits) do
      lines[#lines + 1] = ("   %-46s %-24s = %s"):format(h.rel .. ":" .. h.lnum, h.name, h.value)
    end
    lines[#lines + 1] = ""
  end

  require("insights.ui.scratch").open(lines, "Smells — " .. vim.fn.fnamemodify(root, ":t"))
end

return M
