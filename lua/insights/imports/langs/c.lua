---@module 'insights.imports.langs.c'
---@brief Regex-based C / C++ `#include` scanner.
---
--- `#include <path>` (system/library headers, angle brackets) vs.
--- `#include "path"` (project-local headers, quotes) — the include form
--- itself tells us system vs. local, so `external` is set directly at scan
--- time rather than resolved later from the path string.
local M = {}

local util = require("insights.imports.langs.util")

M.id           = "c"
M.label        = "C/C++"
M.extensions   = { "c", "h", "cc", "cpp", "cxx", "hpp", "hxx", "hh" }
M.rg_prefilter = "#\\s*include"

--- Scan C/C++ source text for #include directives.
---@param src string
---@return { module: string, external: boolean, lnum: integer }[]
function M.scan_source(src)
  local result = {}
  local starts = util.line_starts(src)

  local function scan(pattern, is_ext)
    local pos = 1
    while true do
      local s, e, path = src:find(pattern, pos)
      if not s then break end
      result[#result + 1] = { module = path, external = is_ext, lnum = util.lnum_at(starts, s) }
      pos = e + 1
    end
  end

  scan("#%s*include%s*<([^>]+)>", true)
  scan('#%s*include%s*"([^"]+)"', false)

  return result
end

--- Never called: `scan_source` always sets `external` explicitly per entry.
---@return boolean
function M.is_external()
  return true
end

return M
