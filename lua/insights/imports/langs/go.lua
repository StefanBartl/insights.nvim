---@module 'insights.imports.langs.go'
---@brief Regex-based Go import scanner.
---
--- Handles single-line `import "path"` / `import alias "path"` and grouped
--- `import ( … )` blocks (one import spec per line, each with an optional
--- alias / `.` dot-import / `_` blank-import).
local M = {}

local util = require("insights.imports.langs.util")

M.id           = "go"
M.label        = "Go"
M.extensions   = { "go" }
M.rg_prefilter = "\\bimport\\b"

--- module_path from a project's go.mod, cached per cwd (nil cwd entries are
--- stored as `false` so a missing go.mod isn't re-read on every call).
---@type table<string, string|false>
local module_path_cache = {}

---@param cwd string
---@return string|false
local function module_path(cwd)
  local cached = module_path_cache[cwd]
  if cached ~= nil then return cached end

  local ok, lines = pcall(vim.fn.readfile, cwd .. "/go.mod")
  local found = false
  if ok and type(lines) == "table" then
    for _, l in ipairs(lines) do
      local m = l:match("^module%s+(%S+)")
      if m then found = m; break end
    end
  end
  module_path_cache[cwd] = found
  return found
end

--- Scan Go source text for import specs.
---@param src string
---@return { module: string, name: string|nil, lnum: integer }[]
function M.scan_source(src)
  local result = {}
  local starts = util.line_starts(src)

  -- Grouped: import ( … )
  local pos = 1
  while true do
    local s, e = src:find("import%s*%(", pos)
    if not s then break end
    local close = src:find("%)", e + 1)
    if not close then break end
    local block = src:sub(e + 1, close - 1)

    for off, alias, path in block:gmatch("()[ \t]*([%w_%.]*)[ \t]*[\"']([^\"']+)[\"']") do
      local abs_pos = e + off - 1
      result[#result + 1] = {
        module = path,
        name   = (alias ~= "" and alias) or nil,
        lnum   = util.lnum_at(starts, abs_pos),
      }
    end
    pos = close + 1
  end

  -- Single-line: import "path" / import alias "path" (not the "(" form)
  pos = 1
  while true do
    local s, e, alias, path = src:find("import%s+([%w_%.]*)%s*[\"']([^\"']+)[\"']", pos)
    if not s then break end
    result[#result + 1] = {
      module = path,
      name   = (alias ~= "" and alias) or nil,
      lnum   = util.lnum_at(starts, s),
    }
    pos = e + 1
  end

  return result
end

--- External unless the import path matches (or is a subpackage of) the
--- project's own module path from go.mod; if go.mod is missing, resolution
--- is not possible so every import is reported as external.
---@param module string
---@param cwd string
---@return boolean external
function M.is_external(module, cwd)
  local mp = module_path(cwd)
  if not mp then return true end
  if module == mp or module:sub(1, #mp + 1) == mp .. "/" then
    return false
  end
  return true
end

return M
