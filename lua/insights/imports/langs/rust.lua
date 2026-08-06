---@module 'insights.imports.langs.rust'
---@brief Regex-based Rust import scanner.
---
--- Handles `use a::b::c;`, `use a::{b, c};`, `use a::b::{c, d as e};` with
--- arbitrary brace nesting, and a leading `pub` / `pub(crate)`. Each grouped
--- entry is flattened into its own occurrence with the full `a::b::c` path
--- (rendered with `.` separators so it lines up with the other languages'
--- module strings in the report).
local M = {}

local util = require("insights.imports.langs.util")

M.id = "rust"
M.label = "Rust"
M.extensions = { "rs" }
M.rg_prefilter = "\\buse\\s"

---@internal
--- Expand a (possibly nested) `use` clause into flat `{ path, alias }`
--- entries. `prefix` is the already-resolved path segment accumulated from
--- enclosing groups.
---@param prefix string
---@param clause string
---@return { path: string, alias: string|nil }[]
local function expand(prefix, clause)
  clause = clause:match("^%s*(.-)%s*$")
  if clause == "" then
    return {}
  end

  local base, group = clause:match("^([%w_:]-)::{(.*)}$")
  if group then
    local out = {}
    local sub_prefix = prefix
    if base ~= "" then
      sub_prefix = (prefix ~= "" and (prefix .. "::" .. base) or base)
    end
    for _, part in ipairs(util.split_top_level(group, ",")) do
      vim.list_extend(out, expand(sub_prefix, part))
    end
    return out
  end

  local path, alias = clause:match("^([%w_:]+)%s+as%s+([%w_]+)$")
  path = path or clause
  if path == "*" or path == "" then
    return {}
  end

  local full = (prefix ~= "" and (prefix .. "::" .. path) or path)
  return { { path = (full:gsub("::", ".")), alias = alias } }
end

--- Scan Rust source text for `use` declarations.
---@param src string
---@return { module: string, name: string|nil, lnum: integer }[]
function M.scan_source(src)
  local result = {}
  local starts = util.line_starts(src)

  local pos = 1
  while true do
    local s, e, clause = src:find("%f[%w]use%s+(.-);", pos)
    if not s then
      break
    end
    local lnum = util.lnum_at(starts, s)

    clause = clause:gsub("%s+", " ")

    for _, entry in ipairs(expand("", clause)) do
      result[#result + 1] = { module = entry.path, name = entry.alias, lnum = lnum }
    end
    pos = e + 1
  end

  return result
end

--- `crate::…` / `self::…` / `super::…` are project-internal; everything
--- else is an external crate (from Cargo.toml dependencies or std/core/alloc).
---@param module string
---@return boolean external
function M.is_external(module)
  local head = module:match("^([%w_]+)")
  return not (head == "crate" or head == "self" or head == "super")
end

return M
