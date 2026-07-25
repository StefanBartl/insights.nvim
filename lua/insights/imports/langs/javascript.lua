---@module 'insights.imports.langs.javascript'
---@brief Regex-based JavaScript / TypeScript import scanner.
---
--- Handles `import x from "m"`, `import { a, b as c } from "m"`,
--- `import * as ns from "m"`, `import "m"` (side-effect), `import("m")`
--- (dynamic), and CommonJS `require("m")` (bare or assigned). TS type-only
--- imports (`import type …`, `import { type Foo }`) are recognized and the
--- `type` keyword stripped from the reported name.
local M = {}

local util = require("insights.imports.langs.util")

M.id           = "javascript"
M.label        = "JS/TS"
M.extensions   = { "js", "jsx", "mjs", "cjs", "ts", "tsx" }
M.rg_prefilter = "\\b(import|require)\\b"

---@param tok string
---@return string
local function strip_type_kw(tok)
  return (tok:gsub("^type%s+", ""))
end

--- Parse the clause between `import` and `from "…"` into bound-name entries.
---@param clause string
---@return { name: string, field: string|nil }[]
local function parse_clause(clause)
  clause = strip_type_kw(clause:gsub("[\r\n]", " "):match("^%s*(.-)%s*$"))
  local out = {}

  local ns = clause:match("^%*%s+as%s+([%w_%$]+)$")
  if ns then
    out[#out + 1] = { name = ns, field = "*" }
    return out
  end

  local default_part, named_part = clause:match("^([%w_%$][%w_%$]*)%s*,%s*{(.*)}$")
  if not default_part then
    default_part = clause:match("^([%w_%$][%w_%$]*)$")
  end
  if not named_part then
    named_part = clause:match("^{(.*)}$")
  end

  if default_part then
    out[#out + 1] = { name = default_part }
  end
  if named_part then
    for _, tok in ipairs(util.split_commas(named_part)) do
      tok = strip_type_kw(tok)
      local nm, alias = tok:match("^([%w_%$]+)%s+as%s+([%w_%$]+)$")
      nm = nm or tok
      if nm:match("^[%w_%$]+$") then
        out[#out + 1] = { name = alias or nm, field = alias and nm or nil }
      end
    end
  end

  return out
end

--- Scan JS/TS source text for import/require occurrences.
---@param src string
---@return { module: string, name: string|nil, field: string|nil, lnum: integer }[]
function M.scan_source(src)
  local result = {}
  local starts = util.line_starts(src)
  local consumed = {}

  local function mark(s, e) consumed[#consumed + 1] = { s, e } end
  local function is_consumed(pos)
    for _, r in ipairs(consumed) do
      if pos >= r[1] and pos <= r[2] then return true end
    end
    return false
  end

  -- 1. import <clause> from "mod"  (clause may span multiple lines)
  local pos = 1
  while true do
    local s, e, clause, mod = src:find("import%s+([^;]-)from%s*[\"']([^\"']+)[\"']", pos)
    if not s then break end
    mark(s, e)
    local lnum = util.lnum_at(starts, s)
    local entries = parse_clause(clause)
    if #entries == 0 then
      result[#result + 1] = { module = mod, lnum = lnum }
    else
      for _, en in ipairs(entries) do
        result[#result + 1] = { module = mod, name = en.name, field = en.field, lnum = lnum }
      end
    end
    pos = e + 1
  end

  -- 2. side-effect only: import "mod"
  pos = 1
  while true do
    local s, e, mod = src:find("import%s*[\"']([^\"']+)[\"']", pos)
    if not s then break end
    result[#result + 1] = { module = mod, lnum = util.lnum_at(starts, s) }
    pos = e + 1
  end

  -- 3. dynamic import("mod")
  pos = 1
  while true do
    local s, e, mod = src:find("import%s*%(%s*[\"']([^\"']+)[\"']%s*%)", pos)
    if not s then break end
    result[#result + 1] = { module = mod, lnum = util.lnum_at(starts, s) }
    pos = e + 1
  end

  -- 4a. assigned require: `const x = require("mod")`
  pos = 1
  while true do
    local s, e, name, mod = src:find(
      "([%w_%$][%w_%$%.]*)%s*=%s*require%s*%(%s*[\"']([^\"']+)[\"']%s*%)", pos)
    if not s then break end
    mark(s, e)
    result[#result + 1] = { module = mod, name = name, lnum = util.lnum_at(starts, s) }
    pos = e + 1
  end

  -- 4b. bare require("mod") not already covered by 4a
  pos = 1
  while true do
    local s, e, mod = src:find("require%s*%(%s*[\"']([^\"']+)[\"']%s*%)", pos)
    if not s then break end
    if not is_consumed(s) then
      result[#result + 1] = { module = mod, lnum = util.lnum_at(starts, s) }
    end
    pos = e + 1
  end

  return result
end

--- Relative/absolute specifiers (`./x`, `../x`, `/x`) are project files;
--- bare specifiers (`react`, `@scope/pkg`) are npm packages.
---@param module string
---@return boolean external
function M.is_external(module)
  local first = module:sub(1, 1)
  return not (first == "." or first == "/")
end

return M
