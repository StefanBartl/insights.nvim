---@module 'project_insight.imports.ts_requires'
---@brief Tree-sitter-based Lua require() scanner (AST-accurate).
---
--- Matches only genuine `require("…")` function calls. Because it operates on
--- the syntax tree, the word "require" inside comments or string literals is
--- never matched — unlike the line/regex backend in imports/init.lua.
local M = {}

local api = vim.api
local ts  = vim.treesitter

--- Query: every string argument of a call whose callee is a bare identifier.
--- The identifier is validated to be exactly "require" in Lua afterwards.
local QUERY = [[
  (function_call
    name: (identifier) @fn
    arguments: (arguments (string) @arg))
]]

--- Is the Lua Tree-sitter parser available?
---@return boolean
function M.available()
  return pcall(ts.get_string_parser, "", "lua")
end

--- Strip surrounding quotes / long-bracket markers from a string literal.
---@param s string
---@return string
local function strip_quotes(s)
  return s:match('^"(.*)"$')
    or s:match("^'(.*)'$")
    or s:match("^%[%[(.*)%]%]$")
    or s
end

--- Trailing field access on a require call, e.g. "create" in
--- `require("x").create(...)` or "bar" in `require("x").bar`.
---@param call TSNode
---@param bufnr integer
---@return string|nil
local function trailing_field(call, bufnr)
  local p = call:parent()
  if not p then return nil end
  local t = p:type()
  if t == "dot_index_expression" or t == "method_index_expression" then
    local f = p:field("field")[1] or p:field("method")[1]
    if f then return ts.get_node_text(f, bufnr) end
  end
  return nil
end

--- First named child of `node` with the given type, or nil.
---@param node TSNode
---@param type_name string
---@return TSNode|nil
local function child_of_type(node, type_name)
  for i = 0, node:named_child_count() - 1 do
    local ch = node:named_child(i)
    if ch:type() == type_name then return ch end
  end
  return nil
end

--- Local/assignment variable the require result is bound to. Handles multiple
--- assignment (`local a, b = 1, require(...)`) by index alignment.
---@param call TSNode
---@param src integer|string  buffer handle or source string for get_node_text
---@return string|nil
local function lhs_name(call, src)
  -- Climb through expression-wrapping nodes up to an expression_list.
  local node = call
  local exprlist
  while true do
    local par = node:parent()
    if not par then return nil end
    local pt = par:type()
    if pt == "expression_list" then
      exprlist = par
      break
    elseif pt == "dot_index_expression" or pt == "method_index_expression"
        or pt == "function_call" or pt == "parenthesized_expression" then
      node = par
    else
      return nil  -- bare statement, argument, etc. → no binding
    end
  end

  -- Position of this expression within the expression list.
  local idx
  for i = 0, exprlist:named_child_count() - 1 do
    if exprlist:named_child(i):equal(node) then idx = i; break end
  end
  if not idx then return nil end

  -- assignment_statement exposes variable_list / expression_list as typed
  -- children, not as named fields — find the variable_list by type.
  local assign = exprlist:parent()
  if not assign or assign:type() ~= "assignment_statement" then return nil end
  local vlist = child_of_type(assign, "variable_list")
  if not vlist then return nil end

  local var = vlist:named_child(idx) or vlist:named_child(0)
  return var and ts.get_node_text(var, src) or nil
end

--- Walk a parsed tree and collect require() calls.
---@param root TSNode
---@param src integer|string   buffer handle or source string
---@return { module: string, name: string|nil, field: string|nil, lnum: integer }[]
local function scan_tree(root, src)
  local ok_q, query = pcall(ts.query.parse, "lua", QUERY)
  if not ok_q or not query then return {} end

  local result = {}
  for id, node in query:iter_captures(root, src) do
    if query.captures[id] == "arg" then
      -- node = string < arguments < function_call
      local call = node:parent() and node:parent():parent()
      local fn   = call and call:field("name")[1]
      if fn and ts.get_node_text(fn, src) == "require" then
        local module = strip_quotes(ts.get_node_text(node, src))
        if module ~= "" then
          local row = node:range()
          result[#result + 1] = {
            module = module,
            name   = lhs_name(call, src),
            field  = trailing_field(call, src),
            lnum   = row + 1,
          }
        end
      end
    end
  end

  return result
end

--- Scan one buffer for require() calls.
---@param bufnr integer
---@return { module: string, name: string|nil, field: string|nil, lnum: integer }[]
function M.scan_buffer(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then return {} end

  local ok_p, parser = pcall(ts.get_parser, bufnr, "lua")
  if not ok_p or not parser then return {} end

  local ok_t, trees = pcall(parser.parse, parser)
  if not ok_t or not trees or #trees == 0 then return {} end

  return scan_tree(trees[1]:root(), bufnr)
end

--- Scan a raw Lua source string for require() calls. Used for cwd scans so we
--- never depend on buffer filetype detection.
---@param src string
---@return { module: string, name: string|nil, field: string|nil, lnum: integer }[]
function M.scan_source(src)
  local ok_p, parser = pcall(ts.get_string_parser, src, "lua")
  if not ok_p or not parser then return {} end

  local ok_t, trees = pcall(parser.parse, parser)
  if not ok_t or not trees or #trees == 0 then return {} end

  return scan_tree(trees[1]:root(), src)
end

return M
